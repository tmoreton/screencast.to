#!/usr/bin/env bash
# Builds screencast.app, signs + notarizes + staples it, packages it into a
# styled DMG. By default it also uploads the DMG to Cloudflare R2 for backward
# compatibility with older R2 mirrors; GitHub Releases are the canonical public
# download channel.
#
# Usage:
#   scripts/release.sh                                    # build + upload (reads MARKETING_VERSION)
#   scripts/release.sh 1.0.0                              # explicit version
#   SKIP_UPLOAD=1 scripts/release.sh                      # build only, no R2 upload
#   SKIP_NOTARIZE=1 SKIP_UPLOAD=1 scripts/release.sh      # fastest local test build
#
# Credentials are read from scripts/.env (or already-exported env vars).
# See scripts/.env.example.

set -euo pipefail

cd "$(dirname "$0")/.."

# ---- Args --------------------------------------------------------------------

VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            sed -n '2,16p' "$0"
            exit 0
            ;;
        -*)
            echo "unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -n "$VERSION" ]]; then
                echo "error: unexpected positional argument: $1" >&2
                exit 1
            fi
            VERSION="$1"
            shift
            ;;
    esac
done

# ---- Config ------------------------------------------------------------------

APP_NAME="screencast"
SCHEME="screencast"
PROJECT="screencast.xcodeproj"
CONFIGURATION="Release"

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGING_DIR="$BUILD_DIR/dmg-staging"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
BUILD_SETTINGS_XCCONFIG="$BUILD_DIR/ReleaseBuildSettings.xcconfig"

# Local release credentials. See scripts/.env.example.
if [[ -f scripts/.env ]]; then
    set -a
    # shellcheck disable=SC1091
    source scripts/.env
    set +a
fi

# R2/upload destination. Values come from scripts/.env, exported env vars, or
# worker/.env to match what the Worker reads.
read_worker_env_var() {
    local key="$1"
    [[ -f worker/.env ]] || return 0
    grep -E "^${key}=" worker/.env | head -1 | sed -E "s/^${key}=//" | tr -d '"'
}
APP_SECRET="${APP_SECRET:-$(read_worker_env_var APP_SECRET)}"
R2_BUCKET="${R2_BUCKET:-$(read_worker_env_var R2_BUCKET)}"
R2_PUB_HOST="${R2_PUB_HOST:-$(read_worker_env_var R2_PUB_HOST)}"
R2_DOWNLOAD_PREFIX="downloads"
UPLOAD_WORKER_ENDPOINT="${UPLOAD_WORKER_ENDPOINT:-https://share.screencast.to/sign}"

read_marketing_version() {
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
        -showBuildSettings 2>/dev/null \
        | grep -m1 -E '^[[:space:]]*MARKETING_VERSION = ' \
        | sed -E 's/^[[:space:]]*MARKETING_VERSION = //; s/[[:space:]]*$//'
}

if [[ -z "$VERSION" ]]; then
    VERSION="$(read_marketing_version)"
fi
if [[ -z "$VERSION" ]]; then
    echo "error: could not determine version (pass it as the first argument)" >&2
    exit 1
fi

DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
TEMP_DMG="$BUILD_DIR/$DMG_NAME.tmp.dmg"
APP_ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"

# ---- Decide whether to sign + notarize ---------------------------------------

NOTARIZE=true
NOTARY_AUTH=()

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "==> SKIP_NOTARIZE=1 set; building unsigned/unnotarized DMG for local testing"
    NOTARIZE=false
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    NOTARY_AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
    cat >&2 <<EOF
error: notarization credentials not set.
Either:
  1. Create scripts/.env (see scripts/.env.example) with APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
  2. OR set NOTARY_PROFILE after running:
       xcrun notarytool store-credentials --apple-id you@example.com \\
           --team-id YOUR_TEAM_ID --password xxxx-xxxx-xxxx-xxxx <profile-name>
  3. OR run with SKIP_NOTARIZE=1 for an unnotarized local build
EOF
    exit 1
fi

if [[ "$NOTARIZE" == true && -z "${APPLE_TEAM_ID:-}" ]]; then
    echo "error: APPLE_TEAM_ID is required for notarized Developer ID export." >&2
    exit 1
fi

if [[ "$NOTARIZE" == true && -z "$APP_SECRET" ]]; then
    cat >&2 <<EOF
error: APP_SECRET is required for an official notarized build.
Set APP_SECRET in scripts/.env or worker/.env. Public/dev builds can use
SKIP_NOTARIZE=1 and will compile with upload sharing disabled.
EOF
    exit 1
fi

CODESIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-Developer ID Application}"

xcconfig_value() {
    # In .xcconfig files, // starts a comment. This preserves URL values such as
    # https://share.screencast.to/sign without leaking secrets onto the xcodebuild CLI.
    printf '%s' "$1" | sed 's#//#/$()/#g'
}

write_release_xcconfig() {
    {
        printf 'UPLOAD_WORKER_ENDPOINT = %s\n' "$(xcconfig_value "$UPLOAD_WORKER_ENDPOINT")"
        if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
            printf 'DEVELOPMENT_TEAM = %s\n' "$(xcconfig_value "$APPLE_TEAM_ID")"
        fi
        if [[ "$NOTARIZE" == false ]]; then
            printf 'CODE_SIGNING_ALLOWED = NO\n'
        fi
    } > "$BUILD_SETTINGS_XCCONFIG"
    chmod 600 "$BUILD_SETTINGS_XCCONFIG"
}

set_plist_string() {
    local plist="$1"
    local key="$2"
    local value="$3"
    if /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null; then
        return 0
    fi
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}

inject_upload_config() {
    local app_path="$1"
    local plist="$app_path/Contents/Info.plist"
    if [[ ! -f "$plist" ]]; then
        echo "error: $plist not found" >&2
        exit 1
    fi
    set_plist_string "$plist" "ScreencastWorkerEndpoint" "$UPLOAD_WORKER_ENDPOINT"
    set_plist_string "$plist" "ScreencastUploadSecret" "$APP_SECRET"
}

# ---- Build -------------------------------------------------------------------

echo "==> Building $APP_NAME $VERSION"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$STAGING_DIR" "$DMG_PATH" "$TEMP_DMG" "$APP_ZIP"
mkdir -p "$BUILD_DIR"
write_release_xcconfig

echo "==> Archiving"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    -xcconfig "$BUILD_SETTINGS_XCCONFIG" \
    archive

ARCHIVE_APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
inject_upload_config "$ARCHIVE_APP_PATH"

# ---- Get a Developer-ID-signed .app -----------------------------------------

if [[ "$NOTARIZE" == true ]]; then
    echo "==> Exporting with developer-id signing"
    cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${APPLE_TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS"
    APP_PATH="$EXPORT_DIR/$APP_NAME.app"
else
    APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: $APP_PATH not found" >&2
    exit 1
fi

# ---- Notarize + staple the .app ---------------------------------------------

if [[ "$NOTARIZE" == true ]]; then
    echo "==> Verifying .app signature"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"

    echo "==> Zipping .app for notarization"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

    echo "==> Submitting .app to Apple notary service (this can take a few minutes)"
    xcrun notarytool submit "$APP_ZIP" "${NOTARY_AUTH[@]}" --wait
    rm -f "$APP_ZIP"

    echo "==> Stapling .app"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
fi

# ---- Build DMG ---------------------------------------------------------------

echo "==> Staging DMG contents"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating writable DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -fs HFS+ \
    -format UDRW \
    "$TEMP_DMG" >/dev/null

echo "==> Mounting and styling"
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG")
DEVICE=$(echo "$MOUNT_OUTPUT" | grep -E '^/dev/' | head -n1 | awk '{print $1}')
MOUNT_PATH=$(echo "$MOUNT_OUTPUT" | grep -E "/Volumes/$APP_NAME" | sed -E 's/.*(\/Volumes\/[^	]+)$/\1/')

if [[ -z "$DEVICE" || -z "$MOUNT_PATH" ]]; then
    echo "error: failed to mount $TEMP_DMG" >&2
    exit 1
fi

sleep 1

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 160, 740, 540}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 12
        set label position of viewOptions to bottom
        set position of item "$APP_NAME.app" of container window to {145, 200}
        set position of item "Applications" of container window to {395, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync

echo "==> Detaching"
hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force

echo "==> Compressing"
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$TEMP_DMG"
rm -rf "$STAGING_DIR"

# ---- Sign + notarize + staple the DMG ---------------------------------------

if [[ "$NOTARIZE" == true ]]; then
    echo "==> Signing DMG"
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"

    echo "==> Submitting DMG to Apple notary service"
    xcrun notarytool submit "$DMG_PATH" "${NOTARY_AUTH[@]}" --wait

    echo "==> Stapling DMG"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"

    echo "==> Gatekeeper assessment"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH" || true
fi

echo
echo "==> Built: $DMG_PATH"
ls -lh "$DMG_PATH"

# ---- Upload to Cloudflare R2 -------------------------------------------------

if [[ "${SKIP_UPLOAD:-0}" == "1" ]]; then
    echo
    echo "==> SKIP_UPLOAD=1 set; not uploading to R2."
    exit 0
fi

if [[ -z "$R2_BUCKET" ]]; then
    echo "error: R2_BUCKET not set (looked in worker/.env and env vars)" >&2
    exit 1
fi

DOWNLOAD_KEY_LATEST="$R2_DOWNLOAD_PREFIX/screencast.dmg"
DOWNLOAD_KEY_VERSIONED="$R2_DOWNLOAD_PREFIX/screencast-$VERSION.dmg"

echo
echo "==> Uploading to Cloudflare R2 ($R2_BUCKET)"

upload_to_r2() {
    local key="$1"
    echo "    $key"
    (cd worker && npx wrangler r2 object put "$R2_BUCKET/$key" \
        --remote \
        --file "../$DMG_PATH" \
        --content-type "application/x-apple-diskimage" >/dev/null)
}

upload_to_r2 "$DOWNLOAD_KEY_LATEST"
upload_to_r2 "$DOWNLOAD_KEY_VERSIONED"

echo
echo "✓ Released $APP_NAME $VERSION"
echo
echo "  GitHub Releases should be updated with:"
echo "    gh release upload v$VERSION $DMG_PATH --clobber"
echo
echo "  Legacy R2 mirror:"
echo "    https://${R2_PUB_HOST:-<r2-public-host>}/downloads/screencast.dmg"
echo "    https://${R2_PUB_HOST:-<r2-public-host>}/downloads/screencast-$VERSION.dmg"
