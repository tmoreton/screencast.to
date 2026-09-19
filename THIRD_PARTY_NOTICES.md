# Third-party notices

Screencast.to's own license does not replace the licenses below. Worker
versions are locked in `worker/package-lock.json`; package-level license files
remain the authoritative terms. The website uses no production npm dependency.
The Mac App Store target links only Apple system frameworks. The standalone
macOS target additionally bundles Sparkle 2.10.0;
its complete license and incorporated third-party notices are preserved in
`LICENSES/Sparkle.txt` and copied into the standalone app bundle.

For the separately deployed Worker, the complete copyright notices and license
texts for its locked production dependency closure and observed
Wrangler-injected runtime shim are preserved at
`worker/THIRD_PARTY_LICENSES.txt`. The Worker imports that file as a deployed
text module and serves it at `/third-party-licenses.txt`. Worker dependencies
are not included in the macOS app bundle.

The unified Worker uses Stripe's server SDK 22.6.2 (MIT). Worker packages are
not included in either macOS app target.

## Standalone macOS updater

The Developer ID build uses Sparkle 2.10.0 under its permissive license. It is
linked only to the `screencast-standalone` target and is not present in the Mac
App Store target. Sparkle's `Installer.xpc` service performs installations for
the sandboxed standalone app. Release archives and the appcast are signed with
a project-controlled EdDSA key in addition to Apple's Developer ID signing and
notarization.

## Worker production dependency closure

| Package(s) | Version | License |
|---|---:|---|
| `@apple/app-store-server-library` | 3.1.0 | MIT |
| `aws4fetch` | 1.0.20 | MIT |
| `stripe` | 22.6.2 | MIT |
| `@types/jsonwebtoken`, `@types/jsrsasign`, `@types/ms`, `@types/node`, `@types/node-fetch` | 9.0.10, 10.5.15, 2.1.0, 25.9.6, 2.6.13 | MIT |
| `asynckit`, `base64url`, `call-bind-apply-helpers`, `combined-stream`, `delayed-stream` | 0.4.0, 3.0.1, 1.0.2, 1.0.8, 1.0.0 | MIT |
| `dunder-proto`, `es-define-property`, `es-errors`, `es-object-atoms`, `es-set-tostringtag` | 1.0.1, 1.0.1, 1.3.0, 1.1.2, 2.1.0 | MIT |
| `form-data`, `function-bind`, `get-intrinsic`, `get-proto`, `gopd` | 4.0.6, 1.1.2, 1.3.0, 1.0.1, 1.2.0 | MIT |
| `has-symbols`, `has-tostringtag`, `hasown` | 1.1.0, 1.0.2, 2.0.4 | MIT |
| `jsonwebtoken`, `jsrsasign`, `jwa`, `jws` | 9.0.3, 11.1.5, 2.0.1, 4.0.1 | MIT |
| `lodash.includes`, `lodash.isboolean`, `lodash.isinteger`, `lodash.isnumber`, `lodash.isplainobject`, `lodash.isstring`, `lodash.once` | 4.3.0, 3.0.3, 4.0.4, 3.0.3, 4.0.6, 4.0.1, 4.1.1 | MIT |
| `math-intrinsics`, `mime-db`, `mime-types`, `ms`, `node-fetch`, `safe-buffer`, `undici-types`, `whatwg-url` | 1.1.0, 1.52.0, 2.1.35, 2.1.3, 2.7.0, 5.2.1, 7.24.6, 5.0.0 | MIT |
| `tr46` (including its generated Unicode 8.0 IDNA mapping data) | 0.0.3 | MIT AND Unicode-DFS-2015 |
| `buffer-equal-constant-time` | 1.0.1 | BSD-3-Clause |
| `ecdsa-sig-formatter` | 1.0.11 | Apache-2.0 |
| `semver` | 7.8.5 | ISC |
| `webidl-conversions` | 3.0.1 | BSD-2-Clause |

## Wrangler-injected production runtime

Wrangler 4.131.0's dry-run output injects runtime code from
`unenv@2.0.0-rc.24` (MIT), even though `unenv` enters the lock through the
development toolchain. It is therefore treated as deployed code here. The
dry-run output and source map must be re-audited after a Wrangler upgrade.

### Apple App Store Server Library

Copyright 2023 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

### aws4fetch

Copyright 2018 Michael Hart (michael.hart.au@gmail.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Development-only tools

Direct development dependencies are `@cloudflare/workers-types` (MIT OR
Apache-2.0), `tsx` (MIT), `typescript` (Apache-2.0), and `wrangler` (MIT OR
Apache-2.0). They and most of their transitive and optional platform packages
are build-time-only and are not shipped in the Mac app. Wrangler may inject
selected runtime shims into its deployed bundle; the currently observed
`unenv` shim is documented above and included in the complete Worker notice
file. The complete locked development graph contains MIT, Apache-2.0, MIT OR
Apache-2.0, LGPL-3.0-or-later, CC0-1.0, ISC, 0BSD, and compound
Apache/LGPL/MIT packages. LGPL packages are optional Sharp/libvips build
tooling. Full package names, versions, integrity hashes, and declared licenses
are recorded in `worker/package-lock.json` and the installed package license
files.

GitHub Actions used only in CI (`actions/checkout` and `actions/setup-node`)
are MIT-licensed and are not distributed with the app.

## Platform SDKs, services, assets, and marks

- The app uses Apple system frameworks and StoreKit under Apple's platform and
  developer terms. No Apple framework is vendored.
- Apple Inc. Root, Apple Root CA G2, and Apple Root CA G3 public certificates
  from Apple PKI are embedded in the Worker solely as
  signature-verification trust anchors and remain subject to Apple's terms.
- Cloudflare Workers/R2, Stripe Checkout, GitHub Actions, and App
  Store Connect are hosted service dependencies; their software is not
  vendored here.
- CSS uses system font stacks only. No font file or AI/ML model is bundled.
- The application icon and website screenshot are project assets. Their
  provenance should be confirmed by the rights holder before third-party
  commercial distribution.
- The landing page contains GitHub's Invertocat mark as a link to the source
  repository. That mark belongs to GitHub and is excluded from Screencast.to's
  source license.
