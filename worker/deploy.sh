#!/usr/bin/env bash
# One-shot deploy: validate env, ensure bucket exists, push secrets, deploy worker.
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "✗ worker/.env not found." >&2
  echo "  Copy worker/.env.example to worker/.env and fill in your values." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

required=(R2_ACCOUNT_ID R2_BUCKET R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_PUB_HOST APP_APPLE_ID SERVICE_TOKEN_SECRET)
missing=()
for v in "${required[@]}"; do
  if [ -z "${!v:-}" ]; then
    missing+=("$v")
  fi
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "✗ Missing values in worker/.env: ${missing[*]}" >&2
  exit 1
fi

if [ "${#SERVICE_TOKEN_SECRET}" -lt 32 ]; then
  echo "✗ SERVICE_TOKEN_SECRET must contain at least 32 characters." >&2
  exit 1
fi

if [[ ! "$APP_APPLE_ID" =~ ^[1-9][0-9]*$ ]] ||
   ! node -e 'const value = Number(process.argv[1]); if (!Number.isSafeInteger(value) || value <= 0) process.exit(1)' "$APP_APPLE_ID"; then
  echo "✗ APP_APPLE_ID must be a positive, safely representable decimal App Store ID." >&2
  exit 1
fi

if [ -n "${SELF_HOSTED_UPLOAD_TOKEN:-}" ]; then
  echo "✗ Canonical deployment refuses SELF_HOSTED_UPLOAD_TOKEN because it bypasses App Store entitlement." >&2
  echo "  Private forks must use a distinct Worker name/routes and set UPLOAD_AUTH_MODE=self-hosted." >&2
  exit 1
fi

if [[ ! "$R2_PUB_HOST" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
  echo "✗ R2_PUB_HOST must be a bare DNS hostname without a scheme, port, path, or trailing slash." >&2
  exit 1
fi
R2_PUB_HOST="$(printf '%s' "$R2_PUB_HOST" | tr '[:upper:]' '[:lower:]')"
if [[ "$R2_PUB_HOST" == *.r2.dev ]]; then
  echo "✗ R2_PUB_HOST must be a production R2 custom domain, not an r2.dev development URL." >&2
  exit 1
fi

echo "▶ Ensuring R2 bucket '$R2_BUCKET' exists..."
set +e
bucket_output="$(npx wrangler r2 bucket create "$R2_BUCKET" 2>&1)"
bucket_status=$?
set -e
if [ $bucket_status -ne 0 ]; then
  if echo "$bucket_output" | grep -qi "already exists\|10004"; then
    echo "  (bucket already exists — continuing)"
  else
    echo "$bucket_output" >&2
    echo "✗ Failed to create bucket." >&2
    exit 1
  fi
fi

echo "▶ Applying R2 lifecycle rule (auto-delete after 24h)..."
if [ -f lifecycle.json ]; then
  node -e 'const f=require("./lifecycle.json"); const r=f.rules?.find(x => x.enabled && x.conditions?.prefix === "recordings/" && x.deleteObjectsTransition?.condition?.type === "Age" && x.deleteObjectsTransition?.condition?.maxAge === 86400); if (!r) process.exit(1)' || {
    echo "✗ lifecycle.json does not contain the enabled 24-hour recordings/ rule." >&2
    exit 1
  }
  npx wrangler r2 bucket lifecycle set "$R2_BUCKET" --file lifecycle.json
  lifecycle_output="$(npx wrangler r2 bucket lifecycle list "$R2_BUCKET" 2>&1)"
  echo "$lifecycle_output"
  if ! echo "$lifecycle_output" | grep -q "recordings/"; then
    echo "✗ Lifecycle verification did not show the recordings/ rule." >&2
    exit 1
  fi
else
  echo "✗ lifecycle.json is required; refusing to deploy without the retention rule." >&2
  exit 1
fi

echo "▶ Pushing secrets to Worker..."
npx wrangler secret bulk <<EOF
{
  "R2_ACCOUNT_ID": "${R2_ACCOUNT_ID}",
  "R2_BUCKET": "${R2_BUCKET}",
  "R2_ACCESS_KEY_ID": "${R2_ACCESS_KEY_ID}",
  "R2_SECRET_ACCESS_KEY": "${R2_SECRET_ACCESS_KEY}",
  "R2_PUB_HOST": "${R2_PUB_HOST}",
  "APP_APPLE_ID": "${APP_APPLE_ID}",
  "SERVICE_TOKEN_SECRET": "${SERVICE_TOKEN_SECRET}",
  "MAX_UPLOAD_BYTES": "${MAX_UPLOAD_BYTES:-1073741824}"
}
EOF

echo "▶ Deploying Worker..."
deploy_output="$(npx wrangler deploy 2>&1)"
echo "$deploy_output"

# Extract the *.workers.dev URL from the deploy output (best-effort).
worker_url="$(printf '%s\n' "$deploy_output" | grep -oE 'https://[a-zA-Z0-9.-]+\.workers\.dev' | head -1 || true)"

echo
echo "✓ Deploy complete."
echo
if [ -n "$worker_url" ]; then
  echo "Workers.dev endpoint (diagnostics only; never embed this in an official archive):"
  echo "  $worker_url/sign"
  echo
else
  echo "Could not auto-detect a Workers.dev diagnostics URL from output."
  echo
fi
echo "Verify the production custom domain before creating an App Store archive:"
echo "  https://share.screencast.to/sign"
echo
echo "Official App Store archives always use:"
echo "  SCREENCAST_WORKER_BASE_URL=https://share.screencast.to"
echo
echo "R2_PUB_HOST must point to the bucket's production custom domain."
echo "Keep the Public Development URL disabled for production."
