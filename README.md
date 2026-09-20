<p align="center">
  <img src="checkout/assets/screencast-mark.svg" width="112" height="112" alt="Screencast.to logo">
</p>

<h1 align="center">Screencast.to</h1>

<p align="center">
  A local-first Mac screen recorder for demos, walkthroughs, and bug reports.<br>
  Record the work. Skip the monthly bill.
</p>

<p align="center">
  <a href="https://screencast.to">Website</a> ·
  <a href="https://screencast.to/bundle/">Bundle preview</a> ·
  <a href="SECURITY.md">Security</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

![Screencast.to website and recorder preview](.github/assets/website.png)

> **Release status:** the website, Cloudflare service, and both Mac distribution
> targets are implemented. Direct checkout remains disabled until the first
> Developer ID-signed, notarized DMG and Sparkle feed are published.

## What it does

- Records a full display or a selected region from the macOS menu bar.
- Mixes optional camera, microphone, and system audio.
- Supports pause/resume, live zoom, camera layouts, and a local teleprompter.
- Saves a normal movie to a user-selected location through the standard macOS Save dialog.
- Uploads only after an explicit sharing action; core recording is local.
- Uses no Screencast account, advertising SDK, or behavioral analytics.

Requires macOS 15 or later on Apple silicon or Intel.

## Architecture

| Area | Implementation |
|---|---|
| Mac app | Swift and SwiftUI, with ScreenCaptureKit and AVFoundation |
| Product site | Static HTML, CSS, and JavaScript in `checkout/` |
| Hosted service | One Cloudflare Worker in `worker/` |
| Temporary sharing | StoreKit entitlement verification plus lifecycle-managed R2 storage |
| Direct sales | Stripe Checkout with purchaser-only downloads from private R2 storage |
| Standalone updates | Sparkle 2 with an EdDSA-signed, token-gated private feed |
| App Store updates | Apple-managed; the App Store target contains no Sparkle framework |

Production uses `screencast.to`, `www.screencast.to`, and
`share.screencast.to`. See [the architecture guide](docs/ARCHITECTURE.md) for
the request flows and trust boundaries.

## Repository layout

- `screencast/` — macOS application source and resources.
- `screencast.xcodeproj/` — App Store and standalone build targets.
- `checkout/` — product site, policies, browser code, and private-release
  publishing client.
- `worker/` — Cloudflare APIs, sharing pages, commerce, and R2 access.
- `scripts/` — App Store and Developer ID release scripts.
- `LICENSES/` and `THIRD_PARTY_NOTICES.md` — current and historical license
  records.

## Development

Requirements: macOS 15+, Xcode 26+, and Node.js 24+.

Build the Mac targets without signing:

```sh
xcodebuild -project screencast.xcodeproj -scheme screencast \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project screencast.xcodeproj -scheme screencast-standalone \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Check the website and Worker:

```sh
npm --prefix checkout ci
npm --prefix checkout test
npm --prefix checkout run build

npm --prefix worker ci
npm --prefix worker run check
npm --prefix worker test
npm --prefix worker run smoke
```

Run `npm --prefix checkout start` for a safe static preview. It deliberately
keeps checkout disabled. Use `npm --prefix worker run dev` when testing the
Cloudflare APIs and static assets together.

## Distribution

Screencast.to has two independent release channels:

- The **Mac App Store build** is sandboxed, uses Apple for purchases and
  updates, and may use the first-party temporary-sharing service.
- The **website build** is Developer ID-signed and notarized, is sold through
  Stripe as a one-time purchase, and receives signed Sparkle updates.

Pushing a valid `vMAJOR.MINOR.PATCH` tag starts the private standalone release
workflow. It builds and notarizes the DMG, generates the signed appcast, and
publishes immutable release objects to private Cloudflare R2 storage. It does
not create a public GitHub Release.

Local release commands and required credentials are documented in
[`scripts/.env.example`](scripts/.env.example),
[`checkout/README.md`](checkout/README.md), and
[`worker/README.md`](worker/README.md).

## Privacy and security

Recordings remain local unless the user chooses to upload one. Public source
builds have first-party hosted sharing disabled by default. Self-hosted builds
must use their own Worker, R2 bucket, routes, and credentials.

Do not commit environment files, signing identities, App Store transaction
proofs, service tokens, Stripe keys, Sparkle private keys, or private recording
links. Report vulnerabilities through the process in [SECURITY.md](SECURITY.md).

## Contributing

Bug reports and focused pull requests are welcome. Contributions require the
additional grant described in [CONTRIBUTING.md](CONTRIBUTING.md) so the project
owner can continue distributing both public-source and paid builds.

## License

Current project-owned source is publicly available under
[PolyForm Noncommercial 1.0.0](LICENSE). This is a source-available license,
not an OSI-approved open-source license: personal and other permitted
noncommercial uses are allowed, while commercial use requires separate
permission.

Earlier snapshots retain the licenses granted at the time; those historical
MIT, Apache-2.0, and PolyForm Shield grants are not revoked. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[TRADEMARKS.md](TRADEMARKS.md).
