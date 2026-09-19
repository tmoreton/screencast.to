# Screencast.to checkout

This directory contains the public product site and the server-side direct-sale
path for the standalone Mac app. It mirrors Yaprflow's purchase flow without
sharing its visual identity:

1. `/api/checkout` creates a one-time Stripe Checkout session for the exact
   configured price.
2. Stripe returns to `/api/complete`, which stores the checkout session ID in a
   secure, host-only, HttpOnly cookie.
3. `/api/status` and `/api/download` recheck the session, product marker,
   quantity, mode, payment status, and allowed price with Stripe.
4. A verified customer receives a five-minute signed URL for the current DMG
   in a private Vercel Blob store.
5. Official standalone builds use the token-gated `/api/appcast` and
   `/api/update` endpoints for Sparkle updates. The Mac App Store build has no
   Sparkle dependency and continues to update through Apple.

The DMG, appcast, and release manifest are not public website assets and are
not published through GitHub Releases.

## Local checks

Use Node.js 24 or later:

```sh
npm ci
npm test
npm run build
npm start
```

The site intentionally shows checkout as unavailable until valid test-mode
values from `.env.example` are placed in a gitignored `.env.local` file and a
private release manifest exists. Never put live Stripe keys, Blob credentials,
or the Sparkle update token in source control.

## Vercel setup

Create or link a Vercel project whose root directory is `checkout`, attach a
private Blob store, and configure these production values:

- `STRIPE_SECRET_KEY` — the live secret key for the intended seller account.
- `STRIPE_PRICE_ID` — one active, per-unit, one-time Stripe price.
- `STRIPE_ALLOWED_PRICE_IDS` — optional prior price IDs that retain download
  recovery after future price changes.
- `CHECKOUT_ENABLED=false` — keep production disabled while the live Stripe
  account, signed release, and custom domain are being prepared; change this
  to `true` only after the production preflight passes.
- `CHECKOUT_BASE_URL=https://screencast.to`
- `BLOB_READ_WRITE_TOKEN` — supplied by the linked private Blob store.
- `RELEASE_MANIFEST_PATH=releases/current.json`
- `SPARKLE_UPDATE_TOKEN` — a random value of at least 32 characters; use the
  same GitHub Actions secret when building official standalone releases.
- `RELEASE_PUBLISH_TOKEN` — a separate random value of at least 32 characters;
  store the same value in GitHub Actions. The release workflow exchanges it
  for short-lived, pathname-restricted upload authorization, so the master
  Blob credential never leaves Vercel.

Preview deployments should use Stripe test-mode credentials and keep
`CHECKOUT_ENABLED=false` until a test release has been uploaded. Stripe test
and live objects are distinct, so do not mix a test secret key with a live
price ID.

For Stripe Managed Payments, classify the product before testing Checkout.
Screencast.to uses Stripe tax code `txcd_10202001` (downloadable,
non-recreational software for personal use). Checkout session creation can be
rejected when the product has no eligible tax code.

## Publishing a private release

Pushing a valid `vMAJOR.MINOR.PATCH` tag runs the private release workflow. It
signs and notarizes the standalone app, creates the Sparkle-signed appcast, and
uploads these private objects:

- `releases/screencast-MAJOR.MINOR.PATCH.dmg`
- `releases/appcast-MAJOR.MINOR.PATCH.xml`
- `releases/current.json`

The manifest is written last, so checkout never advertises a partially
published release. GitHub does not receive `BLOB_READ_WRITE_TOKEN`; it uses
`RELEASE_PUBLISH_TOKEN` only to request short-lived access to the expected
release paths. Configure the workflow secrets documented in the root
`README.md` before tagging a release.
