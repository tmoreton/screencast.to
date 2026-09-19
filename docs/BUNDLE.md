# Productivity Bundle readiness — Screencast.to

Last audited: September 19, 2026

## Product record

| Field | Value |
|---|---|
| Product name | Screencast.to |
| Description | A local-first Mac screen recorder with optional, temporary hosted sharing. |
| Apple platforms | macOS 15.0 or later; Apple silicon and Intel |
| Bundle identifier | `to.screencast.app` |
| Current prepared version | 3.0.0 (build 5) |
| Marketing URL | `https://screencast.to` |
| Privacy-policy URL | `https://screencast.to/privacy` |
| Support URL | `https://screencast.to/support` |
| Commercial model | Paid once; no subscription and no Screencast account |
| Planned standalone price | $29 USD |
| License | PolyForm Noncommercial 1.0.0 after commit `e1f237e`; exact historical grants remain unchanged |

The bundle ID is intentionally unchanged so current preferences, permissions,
and sandbox data can remain associated with the app. The product remains
independently useful and purchasable. It has no launcher, shared account,
central authentication service, App Group, or dependency on another bundle
member.

## Primary use cases and features

- Record a full display or selected region from the macOS menu bar.
- Record locally to a QuickTime movie with optional camera, microphone, and
  visible system-audio controls.
- Pause/resume, live zoom, camera layouts, and a local teleprompter.
- Play, reveal in Finder, or delete local recordings without a network service.
- Optionally upload a recording and copy a temporary browser link.

The current implementation does not offer a window picker or multi-display
selector, so marketing must not claim those capabilities.

## Privacy and architecture

All core recording functionality is local. Recordings live under the app's
Application Support `Screencast/Recordings` directory; preferences use the same
bundle's `UserDefaults`. The app has no analytics SDK, advertising, account,
database, App Group, iCloud container, cloud AI, or bundled AI model. The App
Store target has no updater; the standalone target uses Sparkle only for signed
application updates.

The App Store target's sandbox entitlements are limited to outgoing network,
camera, microphone, and screen/system-audio behavior supplied by Apple
frameworks. The standalone target adds only Sparkle's documented installer XPC
mach-service exceptions. Permission descriptions and a privacy manifest are
included. Camera and microphone are optional; onboarding now requires only
Screen Recording for the core feature.
New installs default to screen-only capture with the microphone off. Selecting
an optional input requests its permission when Record is pressed; a denied or
missing input shows recovery guidance without breaking local screen capture.

The website contains no analytics, ads, or tracking code. Its only first-party
cookie records a recent direct-sale purchase so the customer can retrieve the
installer. The App Store privacy questionnaire should
disclose user-provided video/audio uploaded for app functionality as unlinked
and not used for tracking. Purchase proof is processed transiently and is not
retained by the first-party service; confirm the final answers in App Store
Connect against Apple's then-current definitions before submission.

The direct-sale site uses Stripe Checkout for a one-time purchase. After a
successful return, it stores a secure, host-only purchaser cookie for 30 days;
the server revalidates the paid Checkout session before streaming the current
installer. The installer, Sparkle appcast, and release manifest are kept in a
private Cloudflare R2 bucket. The standalone app
uses a build-time update-access token for its Sparkle requests. That token is
an access gate, not unextractable DRM or a per-device license.

## First-party backend

The product site, checkout APIs, private releases, and optional hosted sharing
use one Cloudflare Worker, DNS, separate R2 buckets, and the media custom
domain. The App Store build obtains a locally verified
StoreKit 2 `AppTransaction`, refreshing StoreKit's cached proof after the
user's explicit upload action when necessary, and sends its signed JWS to
`/entitlements/token`. Apple's official server library verifies the signature,
`to.screencast.app`, and environment. It checks Production first with the
numeric App Store app ID, then accepts an Apple-signed Sandbox proof only for
App Review/TestFlight compatibility; Xcode-local proofs are rejected. The
Worker does not log or persist the proof or transaction identifiers. It returns
a stateless 15-minute token with no stable user identifier.

The token authorizes `/sign`, which rate-limits by short-lived IP key and
issues a 15-minute R2 PUT URL limited to `.mov` and bound to the declared
`Content-Length`, `video/quicktime` content type, and `Cache-Control: no-store`.
The default maximum is 1 GiB. Uploaded objects use random link IDs and an R2
lifecycle rule; physical deletion normally completes within 24–48 hours. The
production custom domain must not have a cache rule that overrides `no-store`.

Public builds default to `disabled`. A developer can configure a Worker and
static token they control in `self-hosted` mode. That token cannot authorize
the official service: the canonical Worker is explicitly in `app-store` auth
mode and its deploy script refuses the bypass secret. Private forks must use a
distinct Worker name/routes and explicitly select `self-hosted` mode. The
server-only production token-signing key is never embedded in source or an app
binary.

## Existing-user continuity

- Keep bundle ID `to.screencast.app`, the same signing team, sandbox setting,
  and preference keys.
- `container-migration.plist` moves a pre-sandbox
  `~/Library/Application Support/Screencast` directory into the sandbox on the
  first sandboxed launch where macOS migration applies.
- The migration manifest also brings same-home preferences plus legacy
  `Caches/screencast` and `Caches/notloom` directories into a newly created
  sandbox. The app then moves surviving `.mov` files to Application Support
  without overwriting collisions.
- Very early builds used bundle ID `com.tmoreton.notloom-opus`. A Mac App Store
  app cannot silently read that different app's sandbox; those users need a
  user-selected/manual import path or written recovery instructions. Do not
  delete that old container.
- Retiring the extractable v2.x shared secret will stop new hosted uploads from
  legacy binaries; local recordings remain usable. Existing share links
  continue only until their lifecycle deletion.

An actual Developer ID-to-App Store upgrade must still be tested on a backed-up
copy of real 2.0.2 data before release.

## Third-party software and services

The Mac App Store target uses only Apple system SDKs/frameworks. The standalone
target additionally bundles Sparkle 2.10.0 for Developer ID updates from a
private, EdDSA-signed appcast. The Worker uses Stripe's server SDK 22.6.2,
`@apple/app-store-server-library` 3.1.0 and `aws4fetch` 1.0.20 plus their locked
transitive packages. Complete versions and license families are in
`THIRD_PARTY_NOTICES.md` and `worker/package-lock.json`; complete Worker texts
are embedded as a deployed text module and served at
`/third-party-licenses.txt`. The notice includes Wrangler's observed `unenv`
runtime shim and the Unicode-DFS-2015 terms for `tr46`'s generated Unicode 8.0
IDNA data. No third-party font or AI model is bundled. GitHub's mark and the
Apple Inc. Root, G2, and G3 public root certificates remain separate
third-party materials.

Apple's current Node library transitively installs `jsrsasign` 11.1.5, which
npm reports as unmaintained. The dependency audit reports no known
vulnerabilities, but this should be monitored and upgraded when Apple's
official library changes its verification stack.

Ongoing dependencies/costs are:

- Apple Developer Program membership, App Store commission/tax handling, and
  StoreKit/App Store availability.
- Cloudflare Workers requests/CPU, R2 storage and operations, data delivery as
  applicable, DNS, and the `screencast.to` domain. Certificate verification may
  require a paid Workers plan depending on measured CPU and traffic.
- Stripe transaction fees and dispute/refund administration for direct sales.
- GitHub repository/Actions usage; currently no direct cost is required for the
  public repository within hosted plan limits. GitHub Pages is no longer the
  production website deployment path.
- Abuse response and support time. Uploaded bytes and views are the primary
  variable service cost; the 1 GiB cap and lifecycle reduce exposure.

## App Store and bundle blockers

Code and release paths are prepared, but these owner/portal tasks remain:

1. Confirm the Apple Developer team (historical artifacts show
   `GVXC5FQ2RP`, but the repository cannot prove that is the intended team),
   preserve it for signing continuity, and create or confirm the explicit App
   ID for `to.screencast.app`.
2. Accept the Paid Apps Agreement and create the macOS App Store Connect record,
   SKU, configure the planned $29 USD standalone price, territories,
   tax/banking details, and numeric Apple app ID.
3. Put that numeric ID in the Worker as `APP_APPLE_ID`, rotate/retire the
   extractable legacy `APP_SECRET`, deploy with a strong
   `SERVICE_TOKEN_SECRET`, and attach a production R2 media custom domain.
   Verify a disposable upload returns `Cache-Control: no-store` and a bypassed
   Cloudflare cache status before relying on the deletion promise.
4. Exercise real Production and TestFlight purchase proofs end to end. The
   Worker accepts Apple-signed Sandbox proofs for App Review/TestFlight after a
   Production verification attempt, but deliberately rejects Xcode-local
   AppTransactions.
5. Capture at least one accepted-size Mac App Store screenshot and supply the
   description, keywords, categories, age rating, review notes, privacy labels,
   copyright, trader status, and export-compliance answers. Confirm that mail
   sent to `support@screencast.to` reaches a monitored inbox with a documented
   response/removal process, identify the destination mailbox provider in the
   privacy policy, and operationally honor the stated support-message deletion
   schedule. Current website artwork is not an App Store screenshot.
6. Confirm ownership/provenance of the app icon and the rights applicable to
   the Claude-coauthored commits. Confirm that Tim Moreton, Tim Moreton Jr, and
   Homelab are one rights holder; record an assignment if a company will be the
   licensor.
7. Test migration from the signed 2.0.2 build and decide whether to build a
   manual import flow for the old `com.tmoreton.notloom-opus` container.
8. Decide whether App Review will treat private, unlisted temporary links as
   user-generated content under Guideline 1.2. The viewer now offers a direct
   report/removal link and the operator can remove an R2 object, but the current
   account-free design has no automated content filter or per-user block. If
   those controls are required, launch with official hosted sharing disabled
   until a proportionate moderation design and response process are ready.
9. Bring the historical GitHub release records and every live release mirror
   into license compliance before launch. The Apache-era v2.0.1 and v2.0.2
   release pages must collocate or attach the exact
   [`LICENSES/Apache-2.0.txt`](../LICENSES/Apache-2.0.txt) text alongside their
   binary assets. Do not rewrite commits, tags, or their license history:
   `v2.0` predates the repository's license file and its artifacts were uploaded
   during the brief MIT window, so it must not be retroactively described as
   Apache-2.0, PolyForm Shield, or PolyForm Noncommercial.
10. On real hardware, test every screen/camera/microphone/system-audio
    combination, camera permission denial, and a physical camera disconnect.
    In particular, confirm Camera Only remains opaque and stops without
    exposing desktop frames when the camera disappears; automated checks and
    this build environment cannot exercise those hardware failure paths.
11. Publish and verify the prepared checkout site and Worker before submission.
    Attach `screencast.to` to the Worker only after its Stripe and R2
    production settings are complete; also verify the live privacy and support
    routes and remove the previous free/Apache and analytics language.
12. In the intended Stripe account, create the one-time Screencast.to product
    and price, bind the private `screencast-releases` R2 bucket, and configure
    `STRIPE_SECRET_KEY`, `STRIPE_PRICE_ID`, `SPARKLE_UPDATE_TOKEN`, and
    `RELEASE_PUBLISH_TOKEN`. Run a test-mode purchase, return, download, and
    Sparkle update before switching the site and price to live mode. The
    purchaser-only delivery code is prepared, but no financial account or live
    product is created by this repository change. Decide and configure sales-tax
    collection, receipt emails, the direct-sale refund window, and the support
    process before enabling live checkout.

### Productivity Bundle portal checklist

After each eligible member app is approved and **Ready for Distribution**, an
App Store Connect user with the required role can create the Productivity
Bundle. Screencast.to requires no code-level coupling to Yaprflow or
PaperDrawer; complete these App Store Connect steps instead:

This Apple bundle is separate from direct Stripe purchases. A direct
Screencast.to purchase does not confer Mac App Store ownership, and an App
Store purchase does not create a Stripe purchaser session.

| App | Positioning | Standalone price |
|---|---|---:|
| **Yaprflow** | Wispr Flow alternative | $29 |
| **Screencast.to** | Loom / CleanShot / Screen Studio alternative | $29 |
| **PaperDrawer** | Scanner Pro alternative | $19 |

The three standalone prices total $77 USD. The paid bundle price is still to
be chosen from an eligible App Store price point; it must be at least $29 and
strictly less than $77 under Apple's bundle-pricing rules.

- Select independently downloadable, eligible member apps. All members of a
  paid bundle must be paid; Apple permits up to ten apps in one bundle.
- Supply the bundle-specific name, description, SKU, price, and **Cleared for
  Sale** setting. Add the optional bundle marketing URL if there is a suitable
  public landing page.
- Set a paid-bundle price that is at least the highest individual member-app
  price and strictly less than the sum of all member-app prices.
- Offer the bundle only in territories where every member app is available.
- Check the account-level limits before submission: no more than ten approved
  bundles may be marked **Cleared for Sale** at once, and an individual app may
  appear in no more than three bundles.
