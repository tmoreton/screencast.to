# Screencast.to Cloudflare service

This Cloudflare Worker is the single hosted service for the product website,
Stripe checkout, private standalone releases, Sparkle updates, and optional
temporary recording links. Recording, audio capture, saving, playback, and
local file access through Finder still happen in the Mac app.

The production hostnames are:

- `https://screencast.to` — Cloudflare-hosted marketing, Stripe checkout,
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
is used by this App Store verification path.

### Website purchases

Official website builds connect a paid Stripe purchase once and store an opaque
sharing credential in the Mac's Keychain. The browser's 30-day purchase cookie
is a convenience for connecting; its expiry does not end sharing access on an
already connected Mac.

1. The app opens `/connect-sharing.html` with a random state and an S256 PKCE
   challenge. `POST /api/sharing/authorize` verifies the browser's purchase
   cookie against Stripe and issues a short-lived code bound to that challenge.
2. `POST /api/sharing/exchange` verifies the state and PKCE verifier, consumes
   the code atomically, and returns an encrypted website sharing credential
   plus the same anonymous 15-minute upload token used by the App Store path.
3. `POST /api/sharing/token` renews the upload token and sharing credential.
   Every exchange and renewal rechecks the completed payment, correct product,
   allowlisted price, quantity, mode, and underlying charge. Refunded, partially
   refunded, or disputed charges are rejected. An already issued upload token
   remains valid for at most 15 minutes.
4. Buyers without a browser cookie can request recovery at
   `POST /api/sharing/restore`. A matching paid purchase receives a short-lived
   email link. The response does not disclose whether an address matched.
   `POST /api/sharing/restore/complete` consumes the link and restores the
   browser purchase cookie; it does not bypass the app's PKCE connection.

Connection and recovery tickets live under the private release bucket's
`sharing-auth/` prefix, expire after 15 minutes, and are consumed using a
conditional R2 write. Expired tickets are removed as new tickets are created.
The renewable sharing credential expires after one year, encrypts the purchase
reference with a purpose-specific derived key, and grants no release-publishing
or update-feed access. The signing secret and Stripe key remain server-side;
the native email binding requires no separate mail-provider API key. The app
never contains a shared website upload password.

`UPLOAD_AUTH_MODE=app-store` retains its existing configuration name and accepts
the short-lived upload tokens issued by both official purchase-verification
paths. Website recovery additionally requires the Cloudflare Email Service
configuration below.

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
configuration accepts only server-issued tokens for verified App Store or
website purchases, and `deploy.sh` refuses to install the self-hosted bypass
token.

## Setup

1. Install dependencies:

   ```sh
   npm ci
   ```

2. Log in and create R2 credentials for temporary recording uploads:

   ```sh
   npx wrangler login
   ```

   Create an R2 bucket and an Object Read & Write API token scoped to it. Attach
   a production custom domain to the bucket and keep its Public Development URL
   disabled. Do not configure an Edge Cache TTL rule that overrides the
   objects' `Cache-Control: no-store` metadata.

3. For the canonical service, copy `.env.example` to `.env` and
   supply:

   - R2 account, bucket, access-key, secret-key, and custom media host values.
   - `APP_APPLE_ID`, the numeric ID assigned by App Store Connect.
   - A server-only `SERVICE_TOKEN_SECRET` generated with
     `openssl rand -hex 32`.
   - Leave `SELF_HOSTED_UPLOAD_TOKEN` blank. It is deliberately rejected by
     the canonical deployment script.

4. Add the restricted Stripe key plus the Sparkle and release-publishing tokens
   to the same `.env`, then deploy:

   ```sh
   ./deploy.sh
   ```

The script creates or reuses the recording and private-release buckets, applies
and verifies the `recordings/` lifecycle rule, builds the product site, pushes
secrets, and deploys the Worker. A
lifecycle configuration failure stops deployment so the retention claim cannot
silently drift.

### Website purchase recovery email

Recovery uses Cloudflare Email Service's outbound **Email Sending** feature
through a native Worker binding. It sends only the transactional message
requested by the buyer and creates no newsletter or marketing subscription.
Email Routing alone sends only to verified destination addresses and is not
sufficient for arbitrary customer recipients.

Outbound sending to arbitrary recipients requires Workers Paid and an
onboarded sending domain. The current allowance is 3,000 emails per account
per month, then $0.35 per 1,000 emails; see
[Cloudflare's pricing](https://developers.cloudflare.com/email-service/platform/pricing/).
New accounts also have reputation-based daily limits. Review account
entitlement and limits before enabling customer recovery.

Configure the native binding with a sender restriction and no customer-address
allowlist:

```toml
[[send_email]]
name = "PURCHASE_EMAIL"
allowed_sender_addresses = ["purchases@screencast.to"]
```

The application reads these settings:

| Binding | Purpose |
| --- | --- |
| `PURCHASE_EMAIL` | Native `send_email` binding; no API key is stored in the app or Worker secrets. |
| `PURCHASE_EMAIL_ENABLED` | Exact value `true` enables recovery. Keep `false` until sending is onboarded and verified. |
| `PURCHASE_EMAIL_FROM` | Plain verified sender address: `purchases@screencast.to`. The transport supplies the display name `Screencast.to`. |
| `PURCHASE_EMAIL_REPLY_TO` | Support reply address; defaults to `support@screencast.to`. |

Onboard `screencast.to` under **Email Service → Email Sending**, rather than
Email Routing. Review the outbound authentication records Cloudflare proposes:
`cf-bounce` subdomain MX/SPF records plus the sending DKIM and DMARC records.
Preserve existing apex MX records and incoming-mail forwarding. See
[domain configuration](https://developers.cloudflare.com/email-service/configuration/domains/).
Only after the account and sending domain are ready should
`PURCHASE_EMAIL_ENABLED` be set to `true`. A binding's presence alone does not
make recovery available. Keep local development mocked; enabling a remote email
binding can send real messages.

Account administration requires the Email Sending permission in addition to
ordinary Worker deployment permissions. An existing Wrangler login may lack
that scope. Use an explicitly authorized scoped credential/profile for setup;
the deployed binding itself needs no embedded API token.

The Stripe credential must also permit the website connection flow to read
Customers, Checkout Sessions, Payment Intents, and Charges. The last two are
needed to reject refunded or disputed purchases rather than relying on the
Checkout session's historical paid flag alone. Existing checkout creation and
price/product verification permissions remain necessary.

Restore responses and email failures exclude addresses, provider responses, and
private links from logs. The email transport validates the canonical recovery
URL, escapes its HTML form, uses the structured native email builder, and
requires a message-ID acknowledgement. Automated email tests replace the native
binding with a mock and never send a message. Email Service's quota,
suppression, sender-verification, and delivery errors become a redacted
application error rather than exposing private addresses or links.

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
Website sharing tests also cover purchase/refund checks, PKCE and ticket
redemption, credential renewal, and recovery. `tests/email.test.ts` verifies the
native binding request, enable gate, URL validation, and redaction with mocked
delivery.

## Static site

`npm run build:checkout` exports the canonical product site from `checkout/`
and packages it with the Worker as Cloudflare static assets. The sharing
hostname's home, privacy, support, and viewer pages are rendered directly by
the Worker.

## Retention and operational dependency

`lifecycle.json` expires objects under `recordings/` after one day. Cloudflare
may physically delete expired objects during the following day, so public copy
states that deletion typically occurs within 24–48 hours. Rate limiting is 10
requests per minute per IP for each entitlement/signing route, and the default
upload maximum is 1 GiB.

The service depends on Cloudflare Workers, R2, and DNS/custom-domain service.
App Store verification additionally uses Apple's certificate/StoreKit
infrastructure; website purchase connection uses Stripe and recovery email uses
Cloudflare Email Service. See `docs/ARCHITECTURE.md` for the complete production
topology and distribution boundaries.
