# Architecture

Screencast.to combines a local-first macOS application with one Cloudflare
service. The hosted service is optional for recording and required only for
temporary sharing, direct purchases, private downloads, and standalone
updates.

## Production topology

- `screencast.to` serves the product site, Stripe commerce endpoints,
  purchaser downloads, and Sparkle update delivery.
- `www.screencast.to` redirects permanently to the apex domain.
- `share.screencast.to` serves entitlement verification, temporary-upload
  authorization, viewer pages, privacy information, and support information.
- A lifecycle-managed R2 bucket stores temporary recordings.
- A separate private `screencast-releases` R2 bucket stores versioned DMGs,
  appcasts, and `releases/current.json`.

Cloudflare is authoritative for DNS. Static product-site assets are packaged
with the Worker; release objects are never published as static assets.

## Mac distribution channels

The two Mac targets share the bundle identifier and local data layout but have
separate distribution behavior.

### Mac App Store

The sandboxed App Store target contains no Sparkle framework. Apple handles
purchase, download, and updates. When the user explicitly uploads a recording,
the app sends an Apple-signed StoreKit `AppTransaction` to
`/entitlements/token`. The Worker verifies the certificate chain, bundle ID,
and environment, discards the proof, and returns a stateless 15-minute token
without a stable user identifier.

That token authorizes `/sign`, which returns a short-lived R2 upload URL bound
to the declared size, QuickTime content type, and `Cache-Control: no-store`.
The random share link remains accessible to anyone who has it until the R2
lifecycle removes the recording, normally within 24–48 hours.

### Website edition

The standalone target is Developer ID-signed and notarized. Stripe Checkout
creates one-time purchases for an allowlisted price. A successful return stores
the Checkout session reference in a 30-day, secure, host-only, HttpOnly cookie.
Every status or download request revalidates the session with Stripe before the
Worker streams the current DMG from private R2 storage.

Official standalone builds use Sparkle 2. The appcast and update archive require
a dedicated bearer token and remain protected by Sparkle's EdDSA signature,
Developer ID signing, and Apple notarization. The embedded bearer token is an
access gate for official binaries, not DRM or a per-device license.

## Release publishing

Pushing a valid `vMAJOR.MINOR.PATCH` tag runs the private release workflow:

1. Build and Developer ID-sign the standalone app.
2. Notarize and staple the DMG.
3. Generate an EdDSA-signed Sparkle appcast.
4. Upload the immutable versioned DMG and appcast through `/api/publish`.
5. Validate their metadata and publish `releases/current.json` last.

Checkout can be enabled only when `CHECKOUT_ENABLED=true`, an allowlisted
Stripe price is available, and the current-release manifest is valid.

## Public-source boundary

Public builds keep first-party sharing disabled. A developer may use
`self-hosted` mode only with a distinct Worker name, routes, bucket, and static
token they control. The canonical deployment accepts StoreKit-derived tokens
and refuses the self-hosted bypass secret.

Production secrets belong in Cloudflare Worker secrets, GitHub Actions secrets,
or ignored local environment files. None are required to inspect, build, or
test the public source.
