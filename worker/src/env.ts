/**
 * Worker bindings (secrets + the rate-limit binding). Set via `./deploy.sh`
 * (which calls `wrangler secret bulk`) — see `wrangler.toml` for the names.
 */
export interface Env {
  R2_ACCOUNT_ID: string;
  R2_BUCKET: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_PUB_HOST: string;
  APP_SECRET: string;
  MAX_UPLOAD_BYTES?: string;
  SIGN_LIMITER: { limit: (opts: { key: string }) => Promise<{ success: boolean }> };
}
