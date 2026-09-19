# Contributing

Thanks for helping improve Screencast.to. Bug reports and security reports are
welcome. Unless the maintainer agrees to different terms with you in writing,
by submitting a code, documentation, or asset contribution you grant the
project owner a perpetual, worldwide, non-exclusive, irrevocable,
royalty-free license to use, reproduce, modify, prepare derivative works of,
publicly display, publicly perform, distribute, sublicense, relicense, and sell
that contribution as part of Screencast.to or related products.

You also represent that you have the right to make that grant (including any
required employer permission), that the contribution contains no undisclosed
third-party or generated material, and that any stated third-party license is
compatible with the project. Third-party code, assets, fonts, and models must
keep their own notices and licenses. If you cannot make these grants and
representations, please do not submit the contribution; contact the maintainer
first to discuss separate written terms.

## Local setup

Requirements:

- macOS 15+
- Xcode 26+
- Node.js 24+

Build both app configurations without signing:

```sh
for configuration in Debug Release; do
  xcodebuild \
    -project screencast.xcodeproj \
    -scheme screencast \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    build
done

for configuration in Debug Release; do
  xcodebuild \
    -project screencast.xcodeproj \
    -scheme screencast-standalone \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    build
done
```

Check the Worker and product site:

```sh
cd worker
npm ci
npm run check
npm test
npx wrangler deploy --dry-run

cd ../checkout
npm ci
npm test
npm run build
```

Public builds keep sharing disabled. A developer can use a gitignored local
xcconfig with a Worker and token they control; see
`scripts/Sharing.local.xcconfig.example` and `worker/README.md`.

## Pull requests

- Keep changes scoped to one behavior or cleanup.
- Run the relevant verification before opening a PR.
- Do not commit `.env`, local xcconfig files, certificates, signing keys,
  transaction proofs, service tokens, or private recording links.
- For recording-engine changes, include the scenario tested: pause length,
  system/microphone audio state, capture mode, and macOS version.
- Update `THIRD_PARTY_NOTICES.md` and the relevant package lock when adding a
  dependency.

## Release boundary

`scripts/app-store-release.sh` creates the Mac App Store export and contains no
self-updater. `scripts/release.sh` creates the separate Sparkle-enabled,
Developer ID artifact. Only the tag-triggered `Private Standalone Release`
workflow should publish that artifact and its signed appcast to private
Cloudflare R2 storage through the authenticated Worker route. GitHub Releases
are not part of the standalone delivery path.
