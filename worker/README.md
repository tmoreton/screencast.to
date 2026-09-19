# Screencast.to sharing service

This Cloudflare Worker provides optional, temporary recording links. Recording,
audio capture, saving, playback, and local file access through Finder all happen
in the Mac app without this service.

The production split is:

- `https://screencast.to` — Vercel-hosted marketing, Stripe checkout,
  purchaser downloads, and Sparkle update delivery.
- `https://share.screencast.to` — entitlement, upload-signing, and viewer routes.
- An R2 bucket custom domain — short-lived recording media. Do not use an
  `r2.dev` Public Development URL in production.

## Authorization boundary

Official App Store builds do not contain a service credential:

1. StoreKit verifies `AppTransaction.shared` on the Mac and, if its cached
   proof is unavailable or unverified, refreshes it after the user's explicit
   upload action.
2. The app sends only its signed JWS representation to
   `POST /entitlements/token`.
3. Apple's official server library verifies the certificate chain, bundle ID
   `to.screencast.app`, and the expected environment. Production is checked
   first with the numeric App Store app ID; an Apple-signed Sandbox proof is
   accepted only as the App Review/TestFlight fallback Apple requires.
4. The Worker discards the decoded proof and returns a stateless 15-minute
   bearer token containing no Apple or user identifier.
5. `POST /sign` accepts that token and returns a 15-minute R2 PUT URL for a
   `.mov` recording. Its signed `Content-Length`, `Content-Type`, and
   `Cache-Control: no-store` headers enforce the declared size/type and keep
   temporary recordings out of browser/CDN caches.

The Worker does not log or persist the raw JWS or decoded transaction. No
Screencast account, email address, purchase database, or App Store private key
is used.

Complete license texts for application dependencies and the runtime shim
observed in Wrangler's production bundle are imported as a deployed text module
and served at `GET /third-party-licenses.txt`. Re-run a dry-run bundle audit
after every Wrangler upgrade because build-tool shims can change independently
of the application's production dependency closure.

Public source builds have sharing disabled. For a private deployment, first use
a distinct Worker name and routes, change `UPLOAD_AUTH_MODE` to `self-hosted`,
and configure a private `SELF_HOSTED_UPLOAD_TOKEN`; then build a local app with
matching `SELF_HOSTED_WORKER_BASE_URL` and `SELF_HOSTED_UPLOAD_TOKEN` values.
That static token protects only the developer's infrastructure. The canonical
configuration accepts only StoreKit-derived tokens, and `deploy.sh` refuses to
install the self-hosted bypass token.

## Setup

1. Install dependencies:

   ```sh
   npm ci
   ```

2. Log in and create R2 credentials:

   ```sh
   npx wrangler login
   ```

   Create an R2 bucket and an Object Read & Write API token scoped to it. Attach
   a production custom domain to the bucket and keep its Public Development URL
   disabled. Do not configure an Edge Cache TTL rule that overrides the
   objects' `Cache-Control: no-store` metadata.

3. For the canonical App Store service, copy `.env.example` to `.env` and
   supply:

   - R2 account, bucket, access-key, secret-key, and custom media host values.
   - `APP_APPLE_ID`, the numeric ID assigned by App Store Connect.
   - A server-only `SERVICE_TOKEN_SECRET` generated with
     `openssl rand -hex 32`.
   - Leave `SELF_HOSTED_UPLOAD_TOKEN` blank. It is deliberately rejected by
     the canonical deployment script.

4. Deploy:

   ```sh
   ./deploy.sh
   ```

The script creates or reuses the bucket, applies and verifies the
`recordings/` lifecycle rule, pushes secrets, and deploys the Worker. A
lifecycle configuration failure stops deployment so the retention claim cannot
silently drift.

### Private self-hosted deployment

Do not use the canonical `deploy.sh` for a private service. Copy
`wrangler.toml` to an untracked configuration, give the Worker a distinct name,
replace both official routes with domains you control, and set:

```toml
[vars]
UPLOAD_AUTH_MODE = "self-hosted"
```

Then create the private bucket, apply the same deletion rule, and enter each
binding interactively so credentials do not appear in shell history:

```sh
npx wrangler r2 bucket create YOUR_PRIVATE_BUCKET --config wrangler.self-hosted.toml
npx wrangler r2 bucket lifecycle set YOUR_PRIVATE_BUCKET --file lifecycle.json --config wrangler.self-hosted.toml
npx wrangler secret put R2_ACCOUNT_ID --config wrangler.self-hosted.toml
npx wrangler secret put R2_BUCKET --config wrangler.self-hosted.toml
npx wrangler secret put R2_ACCESS_KEY_ID --config wrangler.self-hosted.toml
npx wrangler secret put R2_SECRET_ACCESS_KEY --config wrangler.self-hosted.toml
npx wrangler secret put R2_PUB_HOST --config wrangler.self-hosted.toml
npx wrangler secret put SELF_HOSTED_UPLOAD_TOKEN --config wrangler.self-hosted.toml
npx wrangler deploy --config wrangler.self-hosted.toml
```

Use a random token of at least 32 characters and the same value in the app's
gitignored sharing configuration. Keep the private Wrangler file untracked.

After deployment, upload a disposable recording and confirm the media response
contains `Cache-Control: no-store` and `CF-Cache-Status: BYPASS` (or `DYNAMIC`)
before treating the 24–48 hour deletion statement as production-ready.

The Apple Inc. Root, Apple Root CA G2, and Apple Root CA G3 certificates are
pinned from [Apple PKI](https://www.apple.com/certificateauthority/) in
`src/apple-root-certificates.ts`. Review them when Apple changes its App Store
certificate chain.

## Local development

```sh
npm run check
npm test
npm run dev
```

An arbitrary or Xcode-local JWS will be rejected. Production AppTransaction
verification also requires a real App Store Connect app record and numeric app
ID. Apple-signed Sandbox proofs support TestFlight and App Review. Focused tests
cover token lifetime, anonymous token contents, authorization, maximum-size
rejection, and signed `Content-Length` behavior.

## Static site

`npm run build:site` exports the marketing, privacy, and support pages to
`../site` as a legacy/fallback export. The canonical product and checkout site
is deployed from `checkout/` to Vercel; do not attach the apex domain to this
Worker or a Pages project. Local exports omit `SITE_CNAME` by default.

## Retention and operational dependency

`lifecycle.json` expires objects under `recordings/` after one day. Cloudflare
may physically delete expired objects during the following day, so public copy
states that deletion typically occurs within 24–48 hours. Rate limiting is 10
requests per minute per IP for each entitlement/signing route, and the default
upload maximum is 1 GiB.

The service depends on Cloudflare Workers, R2, DNS/custom-domain service, and
Apple's certificate/StoreKit infrastructure. See `docs/BUNDLE.md` for the
remaining App Store decisions and expected operating costs.
