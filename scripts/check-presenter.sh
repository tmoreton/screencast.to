#!/usr/bin/env bash
# Exercise the production presenter compositor and layout without camera access.
set -euo pipefail

cd "$(dirname "$0")/.."

presenter_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/screencast-presenter.XXXXXX")"
trap 'rm -rf "$presenter_check_dir"' EXIT

xcrun swiftc \
    -swift-version 5 \
    -default-isolation MainActor \
    -target "$(uname -m)-apple-macosx15.0" \
    -parse-as-library \
    screencast/Recording/RecordingOptions.swift \
    screencast/CameraBubble/PresenterFrameProcessor.swift \
    tests/PresenterChecks.swift \
    -o "$presenter_check_dir/presenter-checks"

"$presenter_check_dir/presenter-checks"
