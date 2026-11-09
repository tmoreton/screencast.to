# Architecture

Screencast.to combines a local-first macOS application with one Cloudflare
service. The hosted service is optional for recording and required only for
temporary sharing, direct purchases, private downloads, and standalone
updates.

## Production topology

- `screencast.to` serves the product site, Stripe commerce endpoints,
  purchaser downloads, website purchase connection, and Sparkle update delivery.
- `www.screencast.to` redirects permanently to the apex domain.
- `share.screencast.to` serves entitlement verification, temporary-upload
  authorization, viewer pages, privacy information, and support information.
- A lifecycle-managed R2 bucket stores temporary recordings.
- A separate private `screencast-releases` R2 bucket stores versioned DMGs,
  appcasts, and `releases/current.json`. Short-lived connection and recovery
  tickets use its separate `sharing-auth/` prefix.
- Cloudflare Email Service delivers requested website-purchase recovery emails
  through a native Worker binding restricted to the configured sender.

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

For optional uploads, the app opens the website's purchase-connection page with
a random state and an S256 PKCE challenge. The Worker verifies the purchase and
returns a short-lived code bound to that app connection. Redemption requires
the matching verifier and consumes the code with an atomic conditional R2
write. The app stores the resulting opaque sharing credential in macOS Keychain;
it does not contain a shared upload password or a Stripe credential.

The sharing credential encrypts the purchase reference using a purpose-specific
key derived from the server-only signing secret. It lasts one year and is
renewed when exchanged for an anonymous 15-minute upload token. Each exchange
rechecks the Stripe product, price, quantity, payment mode, and underlying
charge, rejecting refunded, partially refunded, and disputed purchases. The
upload token uses the same `/sign` and size-bound R2 upload path as the App Store
edition. A payment becoming ineligible prevents renewal; already issued upload
tokens remain valid until their short expiry.

When the browser cookie is missing, the purchaser can request an email to the
address used at checkout. Responses do not disclose whether a purchase matched.
The single-use recovery link restores the browser purchase cookie, after which
the app completes its PKCE connection. Connection and recovery tickets expire
after 15 minutes; expired records are removed as new tickets are created. Cookie
expiry does not disconnect a Mac that already holds a valid Keychain credential.
Recovery remains disabled until the Workers Paid account and outbound sending
domain are ready and `PURCHASE_EMAIL_ENABLED=true`. It uses Email Sending for
arbitrary customer recipients; Email Routing's verified-destination facility
alone is insufficient. Domain setup adds outbound bounce/authentication records
while preserving existing apex MX and incoming forwarding. Configuration is in
[`worker/README.md`](../worker/README.md#website-purchase-recovery-email).

Official standalone builds use Sparkle 2. The appcast and update archive require
a dedicated bearer token and remain protected by Sparkle's EdDSA signature,
Developer ID signing, and Apple notarization. The embedded bearer token is an
access gate for official binaries, not DRM or a per-device license. It is
separate from purchase-linked upload authorization and is never accepted as an
upload credential.

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
token they control. The canonical deployment accepts short-lived upload tokens
issued after StoreKit or website-purchase verification and refuses the
self-hosted bypass secret.

Production secrets belong in Cloudflare Worker secrets, GitHub Actions secrets,
or ignored local environment files. None are required to inspect, build, or
test the public source.
