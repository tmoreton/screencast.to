# Screencast.to

Useful software without another subscription. Screencast.to is a paid,
local-first macOS menu-bar recorder: record a screen or region, mix optional
camera and audio, pause and zoom live, and keep the resulting movie on your
Mac. One purchase, no Screencast account, no ads or tracking, and source you
can inspect.

## Distribution

Version 3.0.0 begins the paid, source-available generation, with two official
distribution channels. The Mac App Store build is updated only by Apple and
includes optional first-party temporary sharing. The separately distributed,
Developer ID-signed build is sold as a one-time purchase and checks a private,
Sparkle-signed update feed. Its installer, appcast, and release manifest live
in private Vercel Blob storage rather than GitHub Releases. Both builds use the
same bundle identifier and local data layout. The planned standalone price is
a one-time $29 purchase.

Developers can also clone and build the source for noncommercial use under the
applicable license. App Store and Productivity Bundle links will be added after
their records exist.

Requires macOS 15 or later on Apple silicon or Intel.

## Local and hosted boundaries

Screen capture, camera/microphone/system-audio capture, recording, playback,
and local file access through Finder run on the Mac. Nothing is uploaded unless
the user clicks the upload control.

The optional official sharing path uses existing Cloudflare Worker and R2
infrastructure. The App Store build sends an Apple-signed StoreKit 2
`AppTransaction` to the Worker, which verifies the production app identity and
returns a short-lived anonymous upload token. The service does not create an
account or retain the proof or Apple transaction identifiers. Uploaded files
are accessible to anyone with their random link and are normally deleted by an
R2 lifecycle rule within 24–48 hours.

Public source builds have hosted sharing disabled by default. Developers can
deploy the Worker and configure their own endpoint and token; cloning the
source does not grant access to the paid first-party service. See
[`worker/README.md`](worker/README.md).

## Repository layout

- `screencast/` — macOS application.
- `checkout/` — product site, Stripe Checkout, purchaser download, and private
  Sparkle delivery endpoints.
- `worker/` — optional Cloudflare Worker/R2 sharing service and website views.
- `scripts/app-store-release.sh` — App Store Connect archive/export path.
- `scripts/release.sh` — Developer ID standalone artifact used by the private
  release workflow; the script itself does not publish anything.
- `docs/BUNDLE.md` — product, App Store bundle, privacy, dependency, cost, and
  launch-blocker record.
- `docs/CLOUDFLARE_MIGRATION.md` — staged plan for moving the commerce site,
  private releases, and Sparkle delivery from Vercel to Workers and R2.

## Development

Build both distribution targets in both configurations without signing:

```sh
xcodebuild -project screencast.xcodeproj -scheme screencast \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project screencast.xcodeproj -scheme screencast-standalone \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project screencast.xcodeproj -scheme screencast-standalone \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project screencast.xcodeproj -scheme screencast \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Check the Worker and exported site:

```sh
cd worker
npm ci
npm run check
npm test
npm run build:site
npx wrangler deploy --dry-run
```

Check the commerce site and purchaser-only delivery service:

```sh
cd checkout
npm ci
npm test
npm run build
```

To test a private Worker, copy `scripts/Sharing.local.xcconfig.example` to a
gitignored `.local.xcconfig` file, fill in that deployment's values, and pass
it to `xcodebuild -xcconfig`. Never use the first-party production service
configuration in a public build.

## Releases

Official production archives require an Apple team and App Store Connect app
record:

```sh
APPLE_TEAM_ID=YOUR_TEAM_ID BUILD_NUMBER=5 scripts/app-store-release.sh 3.0.0
```

The script embeds `app-store` sharing mode and the public Worker base URL, but
no production credential. It exports locally for review and manual upload via
Xcode Organizer or Transporter.

For a local Developer ID standalone artifact, configure Apple notarization,
the Sparkle public key, and the update-access token in `scripts/.env`, then run:

```sh
scripts/release.sh
```

That script never uploads anything. Production private releases are created by
pushing a three-part version tag such as `v3.0.0`; the tag supplies the
standalone artifact's marketing and monotonically increasing internal version.
The `Private Standalone Release` workflow builds and notarizes the DMG,
generates a Sparkle-signed `appcast.xml`, and uploads the installer, appcast,
and current-release manifest to private Vercel Blob storage. It does not create
a GitHub Release. Always publish a version higher than the prior standalone
release.

The workflow requires these repository secrets:

- `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD` for notarization.
- `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD` for Developer ID
  signing.
- `SPARKLE_PRIVATE_ED_KEY` and `SPARKLE_PUBLIC_ED_KEY` from a one-time run of
  Sparkle's `generate_keys` tool.
- `SPARKLE_UPDATE_TOKEN`, a random value of at least 32 characters shared by
  official standalone builds and the private update endpoints.
- `RELEASE_PUBLISH_TOKEN`, a random value of at least 32 characters shared only
  between GitHub Actions and the checkout project's release-publishing route.
  Vercel keeps `BLOB_READ_WRITE_TOKEN`; it is not copied into GitHub.

Keep the Sparkle private key backed up and never commit it. Mac App Store
archives continue to use `scripts/app-store-release.sh`; they do not contain
Sparkle and receive updates through the App Store.

The initial download is available only after the server verifies a paid Stripe
Checkout session; its short-lived URL points to private storage. Sparkle uses a
token-gated appcast and download endpoint. Because a token embedded in a desktop
app can ultimately be extracted, this is an access gate for official binaries,
not DRM or per-device activation. Source licensing remains the legal control on
noncommercial use.

## License

New snapshots are source-available under PolyForm Noncommercial 1.0.0. The
3.0.0 preparation snapshot used PolyForm Shield 1.0.0, and earlier MIT and
Apache-2.0 grants remain available for the historical snapshots and code they
covered; those grants are not revoked. See [`LICENSE`](LICENSE),
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), and
[`TRADEMARKS.md`](TRADEMARKS.md).
