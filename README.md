# Screencast.to

Useful software without another subscription. Screencast.to is a paid,
local-first macOS menu-bar recorder: record a screen or region, mix optional
camera and audio, pause and zoom live, and keep the resulting movie on your
Mac. One purchase, no Screencast account, no ads or tracking, and source you
can inspect.

![Screencast.to website](.github/assets/website.png)

## Distribution

Version 3.0.0 begins the paid, source-available generation. The official Mac
App Store build provides the easiest installation, automatic updates, product
branding, support, and optional first-party temporary sharing. App Store and
Productivity Bundle links will be added after their records exist. The planned
standalone price is a one-time $29 purchase.

Existing GitHub binaries through v2.0.2 remain available as legacy releases,
but new signed production binaries are not published there. Developers can
clone and build the source under the applicable license.

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
- `worker/` — optional Cloudflare Worker/R2 sharing service and website views.
- `scripts/app-store-release.sh` — App Store Connect archive/export path.
- `scripts/release.sh` — local-only Developer ID artifact for development and
  migration testing; it does not publish anything.
- `docs/BUNDLE.md` — product, App Store bundle, privacy, dependency, cost, and
  launch-blocker record.

## Development

Build both configurations without signing:

```sh
xcodebuild -project screencast.xcodeproj -scheme screencast \
  -configuration Debug -destination 'platform=macOS' \
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

For a local Developer ID migration-test artifact:

```sh
scripts/release.sh
```

That script never uploads to R2 or GitHub Releases.

## License

Screencast.to 3.0.0 and later are source-available under PolyForm Shield 1.0.0.
Earlier MIT and Apache-2.0 grants remain available for the historical snapshots
and code they covered; those grants are not revoked. See [`LICENSE`](LICENSE),
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), and
[`TRADEMARKS.md`](TRADEMARKS.md).
