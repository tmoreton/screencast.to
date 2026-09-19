#!/usr/bin/env bash
# Builds the Developer ID artifact distributed outside the Mac App Store.
# It signs and notarizes the app and DMG, but never uploads them. The
# tag-triggered private release workflow calls this script.
#
# Usage:
#   scripts/release.sh                         # reads version/build from Xcode
#   scripts/release.sh 3.0.0                   # explicit embedded version
#   BUILD_NUMBER=6 scripts/release.sh 3.0.0    # explicit embedded build
#   SKIP_NOTARIZE=1 scripts/release.sh          # unsigned local test build
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
SCHEME="screencast-standalone"
PROJECT="screencast.xcodeproj"
CONFIGURATION="Release"

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGING_DIR="$BUILD_DIR/dmg-staging"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
BUILD_SETTINGS_XCCONFIG="$BUILD_DIR/ReleaseBuildSettings.xcconfig"
SOURCE_PACKAGES_DIR="$BUILD_DIR/SourcePackages"

# Local release credentials. See scripts/.env.example.
if [[ -f scripts/.env ]]; then
    set -a
    # shellcheck disable=SC1091
    source scripts/.env
    set +a
fi

SELF_HOSTED_WORKER_BASE_URL="${SELF_HOSTED_WORKER_BASE_URL:-}"
SELF_HOSTED_UPLOAD_TOKEN="${SELF_HOSTED_UPLOAD_TOKEN:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://screencast.to/api/appcast}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_UPDATE_TOKEN="${SPARKLE_UPDATE_TOKEN:-}"

read_marketing_version() {
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
        -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
        -showBuildSettings 2>/dev/null \
        | grep -m1 -E '^[[:space:]]*MARKETING_VERSION = ' \
        | sed -E 's/^[[:space:]]*MARKETING_VERSION = //; s/[[:space:]]*$//'
}

read_build_number() {
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
        -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
        -showBuildSettings 2>/dev/null \
        | grep -m1 -E '^[[:space:]]*CURRENT_PROJECT_VERSION = ' \
        | sed -E 's/^[[:space:]]*CURRENT_PROJECT_VERSION = //; s/[[:space:]]*$//'
}

if [[ -z "$VERSION" ]]; then
    VERSION="$(read_marketing_version)"
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(read_build_number)}"
if [[ -z "$BUILD_NUMBER" ]]; then
    echo "error: could not determine build number (set BUILD_NUMBER)" >&2
    exit 1
fi
if [[ -z "$VERSION" ]]; then
    echo "error: could not determine version (pass it as the first argument)" >&2
    exit 1
fi
if [[ ! "$VERSION" =~ ^[1-9][0-9]*\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "error: version must contain exactly three dot-separated integers, start above zero, and have no leading zeroes" >&2
    exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,3}(\.(0|[1-9][0-9]?)){0,2}$ ]]; then
    echo "error: BUILD_NUMBER must contain one to three dot-separated integers (4/2/2 digit limits), start above zero, and have no leading zeroes" >&2
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
if [[ "$NOTARIZE" == true && -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "error: SPARKLE_PUBLIC_ED_KEY is required for a distributable standalone build." >&2
    exit 1
fi
if [[ "$NOTARIZE" == true && ${#SPARKLE_UPDATE_TOKEN} -lt 32 ]]; then
    echo "error: SPARKLE_UPDATE_TOKEN must contain at least 32 characters for a distributable standalone build." >&2
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
        printf 'MARKETING_VERSION = %s\n' "$(xcconfig_value "$VERSION")"
        printf 'CURRENT_PROJECT_VERSION = %s\n' "$(xcconfig_value "$BUILD_NUMBER")"
        printf 'SPARKLE_FEED_URL = %s\n' "$(xcconfig_value "$SPARKLE_FEED_URL")"
        printf 'SPARKLE_PUBLIC_ED_KEY = %s\n' "$(xcconfig_value "$SPARKLE_PUBLIC_ED_KEY")"
        printf 'SPARKLE_UPDATE_TOKEN = %s\n' "$(xcconfig_value "$SPARKLE_UPDATE_TOKEN")"
        if [[ -n "$SELF_HOSTED_WORKER_BASE_URL" && -n "$SELF_HOSTED_UPLOAD_TOKEN" ]]; then
            printf 'SCREENCAST_SHARING_MODE = self-hosted\n'
            printf 'SCREENCAST_WORKER_BASE_URL = %s\n' "$(xcconfig_value "$SELF_HOSTED_WORKER_BASE_URL")"
            printf 'SCREENCAST_SELF_HOSTED_UPLOAD_TOKEN = %s\n' "$(xcconfig_value "$SELF_HOSTED_UPLOAD_TOKEN")"
        else
            printf 'SCREENCAST_SHARING_MODE = disabled\n'
            printf 'SCREENCAST_WORKER_BASE_URL =\n'
            printf 'SCREENCAST_SELF_HOSTED_UPLOAD_TOKEN =\n'
        fi
        if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
            printf 'DEVELOPMENT_TEAM = %s\n' "$(xcconfig_value "$APPLE_TEAM_ID")"
        fi
        if [[ "$NOTARIZE" == false ]]; then
            printf 'CODE_SIGNING_ALLOWED = NO\n'
        fi
    } > "$BUILD_SETTINGS_XCCONFIG"
    chmod 600 "$BUILD_SETTINGS_XCCONFIG"
}

# ---- Build -------------------------------------------------------------------

echo "==> Building local Developer ID artifact: $APP_NAME $VERSION ($BUILD_NUMBER)"
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
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
    -xcconfig "$BUILD_SETTINGS_XCCONFIG" \
    archive

ARCHIVE_APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

APP_PLIST="$ARCHIVE_APP_PATH/Contents/Info.plist"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
actual_feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP_PLIST")"
actual_public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_PLIST")"
actual_update_token="$(/usr/libexec/PlistBuddy -c 'Print :ScreencastUpdateToken' "$APP_PLIST")"
if [[ "$actual_version" != "$VERSION" ||
      "$actual_build" != "$BUILD_NUMBER" ||
      "$actual_feed_url" != "$SPARKLE_FEED_URL" ||
      "$actual_public_key" != "$SPARKLE_PUBLIC_ED_KEY" ||
      "$actual_update_token" != "$SPARKLE_UPDATE_TOKEN" ]]; then
    echo "error: archived app is $actual_version ($actual_build), expected $VERSION ($BUILD_NUMBER)" >&2
    echo "error: archived Sparkle configuration does not match the release settings" >&2
    exit 1
fi

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

RESOURCES_DIR="$APP_PATH/Contents/Resources"
required_resources=(
    "LICENSE"
    "THIRD_PARTY_NOTICES.md"
    "PolyForm-Noncommercial-1.0.0.md"
    "PolyForm-Shield-1.0.0.md"
    "Apache-2.0.txt"
    "MIT.txt"
    "Sparkle.txt"
)
for resource in "${required_resources[@]}"; do
    if [[ ! -s "$RESOURCES_DIR/$resource" ]]; then
        echo "error: standalone app is missing required resource: $resource" >&2
        exit 1
    fi
done
license_sources=(
    "LICENSE"
    "THIRD_PARTY_NOTICES.md"
    "LICENSES/PolyForm-Noncommercial-1.0.0.md"
    "LICENSES/PolyForm-Shield-1.0.0.md"
    "LICENSES/Apache-2.0.txt"
    "LICENSES/MIT.txt"
    "LICENSES/Sparkle.txt"
)
for license_source in "${license_sources[@]}"; do
    resource="${license_source##*/}"
    if ! cmp -s "$license_source" "$RESOURCES_DIR/$resource"; then
        echo "error: standalone license resource does not match $license_source" >&2
        exit 1
    fi
done
if [[ ! -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]]; then
    echo "error: standalone app does not contain Sparkle.framework" >&2
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
echo
echo "Standalone artifact ready. Publish only through the private release workflow."
