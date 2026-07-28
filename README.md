# Screencast.to

A tiny macOS menu-bar screen recorder. Hit record, capture exactly what you
want — pause/resume, live zoom, camera layouts, teleprompter — and get a
shareable link the moment you stop. Recordings live for 24 hours, then
delete themselves. Always free.

![Screencast.to website](.github/assets/website.png)

## Download

Grab the latest signed and notarized build from
**[GitHub Releases](https://github.com/tmoreton/screencast.to/releases/latest)**,
or from [screencast.to](https://screencast.to) itself.

Requires macOS 15+ (Apple Silicon and Intel).

## Repo layout

- **`screencast/`** — the Xcode project for the Mac app (menu-bar UI, screen
  recording engine, upload client).
- **`worker/`** — the Cloudflare Worker that backs the screencast.to share
  viewer and mints presigned upload URLs. See [`worker/README.md`](worker/README.md)
  for setup and deploy instructions.
- **`scripts/release.sh`** — builds, signs, notarizes, and packages the Mac
  app into a DMG, then uploads it to R2 so screencast.to always serves the
  latest build.

## Releasing a new build

```sh
scripts/release.sh              # reads MARKETING_VERSION from the Xcode project
scripts/release.sh 2.1          # or pass a version explicitly
```

This produces a notarized `build/screencast-<version>.dmg`. To also publish
it as a GitHub release:

```sh
gh release create v<version> build/screencast-<version>.dmg \
  --title "Screencast.to v<version>" \
  --notes "..."
```
