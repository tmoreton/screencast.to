#!/usr/bin/env bash
# Creates an App Store Connect export with anonymous StoreKit-backed sharing.
# This script never uploads an artifact or embeds a production service secret.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="screencast"
SCHEME="screencast"
PROJECT="screencast.xcodeproj"
CONFIGURATION="Release"
EXPECTED_BUNDLE_ID="to.screencast.app"
BUILD_DIR="build/app-store"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
BUILD_SETTINGS_XCCONFIG="$BUILD_DIR/AppStoreBuildSettings.xcconfig"
ARCHIVED_ENTITLEMENTS="$BUILD_DIR/ArchivedAppEntitlements.plist"

if [[ -f scripts/.env ]]; then
    set -a
    # shellcheck disable=SC1091
    source scripts/.env
    set +a
fi

WORKER_BASE_URL="https://share.screencast.to"
if [[ -n "${SCREENCAST_WORKER_BASE_URL:-}" && "$SCREENCAST_WORKER_BASE_URL" != "$WORKER_BASE_URL" ]]; then
    echo "error: App Store archives must use the reviewed official Worker URL: $WORKER_BASE_URL" >&2
    exit 1
fi

if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
    echo "error: APPLE_TEAM_ID is required for App Store signing" >&2
    exit 1
fi
if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "error: APPLE_TEAM_ID must be exactly 10 uppercase letters or digits" >&2
    exit 1
fi

read_build_setting() {
    local key="$1"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
        -showBuildSettings 2>/dev/null \
        | grep -m1 -E "^[[:space:]]*${key} = " \
        | sed -E "s/^[[:space:]]*${key} = //; s/[[:space:]]*$//"
}

VERSION="${1:-$(read_build_setting MARKETING_VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(read_build_setting CURRENT_PROJECT_VERSION)}"
if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
    echo "error: version/build number could not be determined" >&2
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

xcconfig_value() {
    printf '%s' "$1" | sed 's#//#/$()/#g'
}

mkdir -p "$BUILD_DIR"
{
    printf 'DEVELOPMENT_TEAM = %s\n' "$(xcconfig_value "$APPLE_TEAM_ID")"
    printf 'MARKETING_VERSION = %s\n' "$(xcconfig_value "$VERSION")"
    printf 'CURRENT_PROJECT_VERSION = %s\n' "$(xcconfig_value "$BUILD_NUMBER")"
    printf 'SCREENCAST_SHARING_MODE = app-store\n'
    printf 'SCREENCAST_WORKER_BASE_URL = %s\n' "$(xcconfig_value "$WORKER_BASE_URL")"
    printf 'SCREENCAST_SELF_HOSTED_UPLOAD_TOKEN =\n'
} > "$BUILD_SETTINGS_XCCONFIG"
chmod 600 "$BUILD_SETTINGS_XCCONFIG"

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

echo "==> Archiving $APP_NAME $VERSION ($BUILD_NUMBER) for App Store Connect"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    -xcconfig "$BUILD_SETTINGS_XCCONFIG" \
    archive

APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
APP_PLIST="$APP_BUNDLE/Contents/Info.plist"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
if [[ ! -f "$APP_PLIST" ]]; then
    echo "error: archive does not contain the expected app bundle: $APP_BUNDLE" >&2
    exit 1
fi

actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PLIST")"
actual_mode="$(/usr/libexec/PlistBuddy -c 'Print :ScreencastSharingMode' "$APP_PLIST")"
actual_worker_url="$(/usr/libexec/PlistBuddy -c 'Print :ScreencastWorkerBaseURL' "$APP_PLIST")"
actual_self_hosted_token="$(/usr/libexec/PlistBuddy -c 'Print :ScreencastSelfHostedUploadToken' "$APP_PLIST")"
actual_marketing_url="$(/usr/libexec/PlistBuddy -c 'Print :ScreencastMarketingURL' "$APP_PLIST")"
actual_privacy_url="$(/usr/libexec/PlistBuddy -c 'Print :ScreencastPrivacyURL' "$APP_PLIST")"
actual_support_url="$(/usr/libexec/PlistBuddy -c 'Print :ScreencastSupportURL' "$APP_PLIST")"
if [[ "$actual_version" != "$VERSION" ||
      "$actual_build" != "$BUILD_NUMBER" ||
      "$actual_bundle_id" != "$EXPECTED_BUNDLE_ID" ||
      "$actual_mode" != "app-store" ||
      "$actual_worker_url" != "$WORKER_BASE_URL" ||
      "$actual_marketing_url" != "https://screencast.to" ||
      "$actual_privacy_url" != "https://screencast.to/privacy" ||
      "$actual_support_url" != "https://screencast.to/support" ||
      -n "$actual_self_hosted_token" ]]; then
    echo "error: archived app metadata does not match requested App Store build" >&2
    exit 1
fi

required_resources=(
    "PrivacyInfo.xcprivacy"
    "container-migration.plist"
    "LICENSE"
    "THIRD_PARTY_NOTICES.md"
    "PolyForm-Noncommercial-1.0.0.md"
    "PolyForm-Shield-1.0.0.md"
    "Apache-2.0.txt"
    "MIT.txt"
)
for resource in "${required_resources[@]}"; do
    if [[ ! -s "$RESOURCES_DIR/$resource" ]]; then
        echo "error: archived app is missing required resource: $resource" >&2
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
)
for license_source in "${license_sources[@]}"; do
    resource="${license_source##*/}"
    if ! cmp -s "$license_source" "$RESOURCES_DIR/$resource"; then
        echo "error: archived license resource does not match $license_source" >&2
        exit 1
    fi
done
if ! /usr/bin/plutil -lint \
    "$RESOURCES_DIR/PrivacyInfo.xcprivacy" \
    "$RESOURCES_DIR/container-migration.plist" >/dev/null; then
    echo "error: archived privacy or container migration manifest is invalid" >&2
    exit 1
fi
if [[ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]] ||
   /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP_PLIST" >/dev/null 2>&1; then
    echo "error: App Store archive must not contain the standalone Sparkle updater" >&2
    exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"; then
    echo "error: archived app does not have a valid code signature" >&2
    exit 1
fi
if ! /usr/bin/codesign -d --entitlements :- "$APP_BUNDLE" > "$ARCHIVED_ENTITLEMENTS"; then
    echo "error: could not read entitlements from the archived app signature" >&2
    exit 1
fi
actual_app_sandbox="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ARCHIVED_ENTITLEMENTS" 2>/dev/null || true)"
if [[ "$actual_app_sandbox" != "true" ]]; then
    echo "error: archived app signature does not enable the App Sandbox entitlement" >&2
    exit 1
fi

cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>${APPLE_TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
EOF

echo "==> Exporting for App Store Connect"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

echo
echo "==> App Store export ready: $EXPORT_DIR"
echo "Upload it with Xcode Organizer or Transporter after reviewing the archive."
