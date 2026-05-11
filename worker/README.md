# screencast (Cloudflare Worker)

Backs the screencast.to share viewer and mints presigned PUT URLs for the Mac app to upload recordings directly to Cloudflare R2.

## One-time setup

1. **Install deps**
   ```sh
   cd worker
   npm install
   ```

2. **Log in to Cloudflare**
   ```sh
   npx wrangler login
   ```

3. **Create the R2 bucket** in the dashboard (e.g. `screencast-recordings`). Under the bucket's *Settings* tab, enable **Public Development URL** and note the `pub-<hash>.r2.dev` host that appears.

4. **Create an R2 API token**
   Dashboard → **R2** → *Manage R2 API Tokens* → **Create API Token**.
   - Permissions: **Object Read & Write**
   - Specify bucket: your bucket name
   Save the **Access Key ID** and **Secret Access Key**.

5. **Generate a shared app secret**
   ```sh
   openssl rand -hex 32
   ```
   You'll paste this into both `worker/.env` (`APP_SECRET=...`) and `notloom-opus/Upload/Config.local.swift`.

6. **Fill in `worker/.env`** — copy `worker/.env.example` and replace the empty values.

7. **Deploy**
   ```sh
   ./deploy.sh
   ```
   The script validates the env, creates the bucket if needed, applies the 24h lifecycle rule, pushes all secrets in one shot, and runs `wrangler deploy`. Idempotent — safe to re-run.

8. *(Optional)* **Wire up the screencast.to custom domain**
   Once `screencast.to` is a zone in your Cloudflare account, the route in `wrangler.toml` will activate on the next `./deploy.sh`. Share URLs then look like `https://screencast.to/v/<id>.mov` instead of the workers.dev URL.

## Subsequent deploys

- **Code-only change** to `src/worker.ts`: `npx wrangler deploy` is enough.
- **Secret rotation** (new R2 keys, new `APP_SECRET`, etc.): use `./deploy.sh` again — it bulk-pushes secrets.

## Local dev

```sh
npx wrangler dev
# in another terminal:
curl -X POST http://localhost:8787/sign \
  -H 'content-type: application/json' \
  -H "X-Screencast-Auth: $(grep APP_SECRET .env | cut -d= -f2)" \
  -d '{"ext":"mov"}'
```

You should get back `{ "uploadUrl": "...", "publicUrl": "..." }`.

## How it works

- Mac app `POST /sign` with `X-Screencast-Auth` → Worker checks the secret, rate-limits per-IP (10/min), generates a 10-char short ID, signs a 15-minute presigned PUT URL with [aws4fetch](https://github.com/mhart/aws4fetch), returns `{ uploadUrl, publicUrl }`.
- Mac app `PUT`s the file body to `uploadUrl` (no signed headers; only the host is signed).
- Object lands at `recordings/<id>.<ext>` in the bucket.
- Anyone visiting `publicUrl` (`/v/<id>.<ext>`) gets the fullscreen viewer page; the page's `<video>` tag fetches the actual file from R2's public `pub-XXX.r2.dev` host.

**Why not sign `Content-Type`?** Per Cloudflare's R2 docs, signing `Content-Type` while using `signQuery: true` causes uploads from non-curl clients to be rejected as unsigned. So we only sign the host.

## Auto-delete

`lifecycle.json` is applied on every `./deploy.sh` and tells R2 to delete anything in `recordings/` after 1 day (actual deletion happens within 24–48h of upload).
