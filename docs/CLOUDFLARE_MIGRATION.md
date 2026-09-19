# Cloudflare production architecture

Screencast.to is deployed as one Cloudflare Worker with three custom domains:

- `screencast.to` serves the static product site, Stripe Checkout APIs,
  purchaser-only downloads, and token-gated Sparkle updates.
- `www.screencast.to` permanently redirects to the apex.
- `share.screencast.to` serves App Store entitlement verification, temporary
  recording upload authorization, and recording viewers.

Cloudflare remains authoritative for DNS. Static assets ship with the Worker.
Temporary recordings remain in their lifecycle-managed R2 bucket. Standalone
DMGs, appcasts, and `releases/current.json` live in the separate private
`screencast-releases` bucket, which has no public development URL and no
recording-expiration rule.

## Safety boundaries

- `CHECKOUT_ENABLED` remains `false` until a Developer ID-signed, notarized,
  stapled DMG and signed Sparkle appcast have been published.
- Checkout accepts one allowlisted one-time Stripe price and revalidates the
  paid session before every purchaser download.
- Versioned release objects are immutable. The release workflow uploads the
  DMG and appcast first and publishes the current manifest only after their
  sizes and DMG checksum metadata match.
- Release publication and Sparkle use independent bearer tokens. Neither token
  is written to the repository or browser-visible assets.
- The Mac App Store target contains no Sparkle framework and continues to
  receive updates only through Apple.

## Deployment

`worker/deploy.sh` validates configuration, ensures both R2 buckets exist,
applies the temporary-recording lifecycle rule, builds the checkout assets,
installs Worker secrets, and deploys all three custom domains. The private
release bucket is bound directly to the Worker; customers never receive R2
credentials or a public R2 hostname.

The tagged standalone release workflow calls
`https://screencast.to/api/publish`, uploads the notarized DMG and signed
appcast through the authenticated Worker, and writes the manifest last.

## Launch gate

Before setting `CHECKOUT_ENABLED=true`:

1. Configure the five Apple/Developer ID GitHub Actions secrets:
   `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`,
   `DEVELOPER_ID_P12_BASE64`, and `DEVELOPER_ID_P12_PASSWORD`.
2. Push the first valid production version tag and let the release workflow
   build, notarize, staple, Sparkle-sign, and publish the release.
3. Verify `/api/config` reports the expected live price and
   `downloadReady: true` while checkout is still disabled.
4. Complete a Stripe test-mode purchase against a non-production Worker, then
   smoke-test live Checkout session creation without completing a charge.
5. Enable checkout and immediately verify the paid download and Sparkle feed.

## Rollback and Vercel cleanup

The former Vercel project is not part of the production request path once the
Cloudflare custom domains are verified. Keep its last known-good deployment
for a short observation window, but remove the apex and `www` domain bindings
so it cannot reclaim production traffic. Deleting its private Blob objects or
project is a separate irreversible retention decision.

If Cloudflare fails during the observation window, keep checkout disabled and
reattach the public domains to the last verified deployment. Public API paths
remain stable, so no desktop application change is required.
