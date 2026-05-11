# notloom-uploads (Cloudflare Worker)

Mints short-lived presigned PUT URLs for the notloom Mac app to upload directly to a Cloudflare R2 bucket.

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

3. **Create the R2 bucket** in the Cloudflare dashboard (e.g. `notloom-recordings`). Under the bucket's *Settings* tab, enable **Public Development URL** and note the `pub-<hash>.r2.dev` host that appears.

4. **Create an R2 API token**
   Dashboard → **R2** → *Manage R2 API Tokens* → **Create API Token**.
   - Permissions: **Object Read & Write**
   - Specify bucket: `notloom-recordings`
   Save the **Access Key ID** and **Secret Access Key**.

5. **Set secrets**
   ```sh
   npx wrangler secret put R2_ACCOUNT_ID         # your Cloudflare account ID
   npx wrangler secret put R2_BUCKET             # e.g. notloom-recordings
   npx wrangler secret put R2_ACCESS_KEY_ID      # from step 4
   npx wrangler secret put R2_SECRET_ACCESS_KEY  # from step 4
   npx wrangler secret put R2_PUB_HOST           # e.g. pub-abc123.r2.dev
   ```

6. **Deploy**
   ```sh
   npx wrangler deploy
   ```
   Copy the `*.workers.dev` URL it prints, append `/sign`, and paste into
   `notloom-opus/Upload/Config.swift` as the `workerEndpoint` value.

## Local dev

```sh
npx wrangler dev
# in another terminal:
curl -X POST http://localhost:8787/sign -H 'content-type: application/json' -d '{"ext":"mov"}'
```

You should get back `{ "uploadUrl": "...", "publicUrl": "...", "key": "recordings/<uuid>.mov" }`.

## How it works

- Client POSTs to `/sign` → Worker generates a UUID, signs a 15-minute presigned PUT URL with [aws4fetch](https://github.com/mhart/aws4fetch) (`signQuery: true`, so the signature lives in the URL and the client doesn't need to send any signed headers).
- Client PUTs the file body to that URL.
- Object lands at `recordings/<uuid>.<ext>` in the bucket; the public URL is `https://<R2_PUB_HOST>/recordings/<uuid>.<ext>`.

**Why not sign Content-Type?** Per Cloudflare's R2 docs, signing `Content-Type` while using `signQuery: true` causes uploads from non-curl clients to be rejected as unsigned. So we only sign the host (the default with `signQuery: true`).
