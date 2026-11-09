#!/usr/bin/env bash
# Check real local recording storage without launching the app or Finder.
set -euo pipefail

cd "$(dirname "$0")/.."

library_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/screencast-library.XXXXXX")"
trap 'rm -rf "$library_check_dir"' EXIT

xcrun swiftc \
    -swift-version 5 \
    -default-isolation MainActor \
    -target "$(uname -m)-apple-macosx15.0" \
    -parse-as-library \
    screencast/Recording/RecordingLibrary.swift \
    tests/RecordingLibraryChecks.swift \
    -o "$library_check_dir/library-checks"

"$library_check_dir/library-checks"
