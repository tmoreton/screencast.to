#!/usr/bin/env bash
# Check the production PKCE/callback helpers without browser or Keychain access.
set -euo pipefail

cd "$(dirname "$0")/.."

sharing_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/screencast-sharing.XXXXXX")"
trap 'rm -rf "$sharing_check_dir"' EXIT

xcrun swiftc \
    -swift-version 5 \
    -default-isolation MainActor \
    -target "$(uname -m)-apple-macosx15.0" \
    -parse-as-library \
    screencast/Upload/Config.swift \
    screencast/Upload/WebsiteSharingManager.swift \
    tests/WebsiteSharingChecks.swift \
    -o "$sharing_check_dir/sharing-checks"

"$sharing_check_dir/sharing-checks"
