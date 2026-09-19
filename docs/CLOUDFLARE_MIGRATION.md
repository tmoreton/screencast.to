# Cloudflare commerce migration plan

## Recommendation

Launch the paid standalone channel on the existing Vercel checkout stack, then
migrate only after a notarized production release and the complete purchase
flow have been proven. Cloudflare remains the authoritative DNS provider during
both phases. The existing `share.screencast.to` Worker and temporary-recording
R2 bucket are independent of the commerce migration and stay online throughout.

The reason to migrate later is operational and economic, not functional:
Cloudflare Workers can serve the static site and commerce APIs, while a private
R2 bucket can hold the DMG, appcast, and current-release manifest without R2
internet-egress fees. The cost is a real storage and runtime port plus another
complete checkout/release verification cycle.

## Current production boundaries

| Concern | Current owner | Stable public contract |
| --- | --- | --- |
| DNS | Cloudflare | `screencast.to`, `www.screencast.to`, `share.screencast.to` |
| Product site and commerce APIs | Vercel | `https://screencast.to` and `/api/*` |
| Installer, appcast, release manifest | Private Vercel Blob | Available only through authenticated site APIs |
| Payments | Stripe | One-time live price; server-side restricted key |
| Temporary recording sharing | Cloudflare Worker and R2 | `https://share.screencast.to` |
| App Store distribution | Apple | App Store updates; no Sparkle framework |
| Standalone distribution | GitHub Actions, Vercel, Sparkle | Notarized DMG and token-gated update feed |

The hostname and API paths should not change during migration. Keeping
`https://screencast.to/api/appcast` and `/api/update` stable means existing
standalone builds do not need an update merely because the backend moves.

## Launch gate before any migration

Do not enable production checkout until all of the following are true:

1. Add the five Apple/Developer ID GitHub Actions secrets:
   `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`,
   `DEVELOPER_ID_P12_BASE64`, and `DEVELOPER_ID_P12_PASSWORD`.
2. Push the first production version tag and let `Private Standalone Release`
   build, Developer ID-sign, notarize, staple, Sparkle-sign, and publish it.
3. Verify the published manifest names that version and the DMG checksum and
   size match the workflow artifact. An unsigned local test DMG is never a
   sellable release.
4. Exercise Stripe test checkout end to end, including confirmation, paid
   status, the five-minute installer URL, and a Sparkle update request.
5. Smoke-test production session creation without completing a real charge,
   then enable `CHECKOUT_ENABLED=true` and redeploy.
6. Revoke the unused full-access Stripe key after the restricted production
   key has passed these checks.

## Target Cloudflare design

Use a dedicated commerce Worker rather than adding commerce responsibilities
to the recording-sharing Worker. This preserves separate failure, secret, and
deployment boundaries:

- `screencast-commerce`: static assets plus `/api/config`, `/api/checkout`,
  `/api/complete`, `/api/status`, `/api/download`, `/api/appcast`,
  `/api/update`, and `/api/publish`.
- `screencast` (existing): App Store entitlement verification, upload signing,
  and recording viewers on `share.screencast.to`.
- `screencast-releases` R2 bucket: private, immutable versioned DMGs and
  appcasts plus the mutable `releases/current.json` pointer. It must not share
  the 24-hour recording lifecycle rule.

The commerce Worker should keep the existing validation rules: an allowlisted
one-time Stripe price, live/test-mode matching, host-only purchase cookie,
same-origin checkout creation, paid-session revalidation, five-minute release
URLs, constant-time bearer-token checks, strict release pathnames, and a
manifest written only after both versioned artifacts exist.

## Code changes

1. Move the exported `checkout/public` assets into the commerce Worker's static
   assets configuration. Retain the current security headers and redirects.
2. Keep the framework-neutral logic under `checkout/lib`, replacing only the
   Vercel adapters:
   - `process.env` becomes typed Worker bindings.
   - Vercel function entry points become one Worker router.
   - `@vercel/blob` reads and signed URLs become R2 `get()` calls or short-lived
     S3-compatible presigned GET URLs.
   - Vercel client-upload authorization becomes a release-token-protected
     endpoint that issues pathname-, method-, content-type-, size-, and
     expiry-constrained R2 presigned PUT URLs.
3. Keep Stripe secret keys, update tokens, and release-publish tokens as Worker
   secrets. Keep public configuration and resource bindings in Wrangler.
4. Point `checkout/scripts/publish-release.mjs` at the unchanged
   `https://screencast.to/api/publish` contract, but swap its Vercel upload
   client for direct PUTs to the returned R2 URLs.
5. Add Worker integration tests using local R2 bindings/fakes and reuse the
   existing handler, purchase, manifest, and website tests.

## Deployment and release changes

### Website deployments

- Pull requests deploy a non-production commerce Worker name with test Stripe
  credentials, a separate R2 bucket, and checkout disabled by default.
- Merges to `main` deploy the production commerce Worker without changing the
  release bucket contents or enabling checkout automatically.
- Wrangler configuration must never attach `screencast.to` to the existing
  recording-sharing Worker.

### Standalone releases

The tag workflow remains responsible for the complete artifact transaction:

1. Build and Developer ID-sign the standalone app.
2. Notarize and staple the app/DMG.
3. Generate the EdDSA-signed Sparkle appcast.
4. Request short-lived upload URLs from `/api/publish`.
5. Upload the immutable versioned DMG and appcast to R2.
6. Upload `current.json` last so users never observe a partial release.
7. Read the manifest back and compare version, size, and SHA-256 before the
   workflow succeeds.

The Mac App Store archive and update path remain unchanged and do not contain
Sparkle.

## Migration sequence

1. Create the dedicated private release bucket and staging commerce Worker.
2. Port the runtime/storage adapters while preserving API response contracts.
3. Copy every release object from Vercel Blob to R2 and verify SHA-256 hashes.
4. Run unit tests, Worker tests, a Stripe sandbox purchase, authenticated DMG
   download, and Sparkle-feed/update checks against the staging hostname.
5. Deploy production with checkout still disabled and test all nonfinancial
   endpoints on its `workers.dev` hostname.
6. Temporarily disable checkout, attach `www.screencast.to`, verify its redirect,
   then attach `screencast.to` to the commerce Worker.
7. Re-run production smoke tests and enable checkout only after the exact
   notarized release is downloadable.
8. Keep the Vercel project and Blob store intact but read-only for at least
   seven days as the rollback target.
9. After the observation window, remove Vercel custom domains and production
   secrets; delete Blob objects only after a separately approved backup and
   retention decision.

## Rollback

If the Worker, Stripe integration, R2 download, or Sparkle path fails, disable
checkout and reattach the apex and `www` domains to the verified Vercel
deployment. Because the public hostname and API routes are stable, no desktop
release rollback is required. Do not remove Vercel or its private release
objects until the Cloudflare observation window has passed.

## Definition of done

- The root and `www` domains resolve only to the commerce Worker; `www`
  redirects to the root.
- `share.screencast.to` remains on the existing sharing Worker.
- The live page shows the Stripe price and creates a Checkout session only when
  a valid R2 release manifest exists.
- A paid session can download the notarized DMG, while an unpaid session cannot.
- Sparkle can fetch its signed appcast and versioned DMG; App Store builds still
  update only through Apple.
- Release uploads are short-lived and limited to the expected versioned paths.
- Logs contain no Stripe secrets, update tokens, Apple transaction JWS values,
  purchaser cookies, or signed R2 URLs.
- Vercel can be removed without changing the app, public URLs, or release
  procedure visible to customers.
