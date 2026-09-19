# Screencast.to website

This directory contains the static product site and the small client used by
the private standalone-release workflow. Production API routes live only in
the unified Cloudflare Worker under `../worker`.

## Local development

Use Node.js 24 or later:

```sh
npm ci
npm test
npm run build
npm start
```

The local preview serves a deliberately disabled `/api/config` response. It
cannot create purchases, read private releases, or use production credentials.
For end-to-end API testing, build the site and run the Worker instead:

```sh
npm run build
npm --prefix ../worker run dev
```

Generated files are written to `public/` and are ignored by Git. Wrangler
packages that directory as Cloudflare static assets.

## Production flow

The Worker owns every server-side step:

1. `/api/checkout` creates an allowlisted one-time Stripe Checkout session.
2. `/api/complete` stores the session reference in a secure, host-only,
   HttpOnly cookie.
3. `/api/status` revalidates the product, price, quantity, mode, and payment.
4. `/api/download` streams the current DMG from a private R2 bucket only after
   successful verification.
5. `/api/appcast` and `/api/update/<file>` deliver token-gated Sparkle updates to
   official standalone builds.

The Mac App Store build does not use these update routes; Apple supplies its
downloads and updates.

## Private release publishing

`scripts/publish-release.mjs` uploads a versioned DMG and appcast through the
Worker's authenticated `/api/publish` route, then writes
`releases/current.json` last. Versioned objects are immutable, and neither the
installer nor the appcast is stored in the website or a public GitHub Release.

The tag-triggered workflow supplies `RELEASE_PUBLISH_TOKEN`; do not place that
token or any Stripe, R2, Apple, or Sparkle credential in this directory.
