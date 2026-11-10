/**
 * Worker bindings (secrets + the rate-limit binding). Set via `./deploy.sh`
 * (which calls `wrangler secret bulk`) — see `wrangler.toml` for the names.
 */
export interface Env {
  ASSETS: Fetcher;
  UPLOAD_AUTH_MODE: "app-store" | "self-hosted";
  R2_ACCOUNT_ID: string;
  R2_BUCKET: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_PUB_HOST: string;
  APP_APPLE_ID: string;
  SERVICE_TOKEN_SECRET: string;
  PURCHASE_EMAIL?: SendEmail;
  PURCHASE_EMAIL_ENABLED?: string;
  PURCHASE_EMAIL_FROM?: string;
  PURCHASE_EMAIL_REPLY_TO?: string;
  SELF_HOSTED_UPLOAD_TOKEN?: string;
  MAX_UPLOAD_BYTES?: string;
  RELEASES: R2Bucket;
  CHECKOUT_BASE_URL: string;
  CHECKOUT_ENABLED: string;
  STRIPE_PRICE_ID: string;
  STRIPE_ALLOWED_PRICE_IDS?: string;
  STRIPE_COMPLIMENTARY_COUPON_ID?: string;
  RELEASE_MANIFEST_PATH?: string;
  STRIPE_SECRET_KEY: string;
  SPARKLE_UPDATE_TOKEN: string;
  RELEASE_PUBLISH_TOKEN: string;
  SIGN_LIMITER: { limit: (opts: { key: string }) => Promise<{ success: boolean }> };
}
