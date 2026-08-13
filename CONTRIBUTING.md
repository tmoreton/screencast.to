# Contributing

Thanks for helping improve Screencast.to.

## Local Setup

Requirements:

- macOS 15+
- Xcode 26+
- Node.js 22+

Build the Mac app without signing:

```sh
xcodebuild \
  -project screencast.xcodeproj \
  -scheme screencast \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Check the Worker:

```sh
cd worker
npm ci
npm run check
npm run build:site
```

Public builds compile with upload sharing disabled. Official signed builds
inject `APP_SECRET` and `UPLOAD_WORKER_ENDPOINT` through `scripts/release.sh`.

## Pull Requests

- Keep changes scoped to one behavior or cleanup.
- Run the relevant verification before opening a PR.
- Do not commit `.env`, certificates, signing keys, or generated `site/` output.
- For recording-engine changes, include the scenario tested: pause length,
  microphone/system audio state, capture mode, and macOS version.

## Release Notes

Maintainer releases use:

```sh
scripts/release.sh
```

The script builds a signed/notarized DMG and can upload it to R2. GitHub
Releases remain the canonical public download channel.
