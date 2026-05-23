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

required=(R2_ACCOUNT_ID R2_BUCKET R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_PUB_HOST APP_SECRET)
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
  set +e
  lifecycle_output="$(npx wrangler r2 bucket lifecycle set "$R2_BUCKET" --file lifecycle.json 2>&1)"
  lifecycle_status=$?
  set -e
  if [ $lifecycle_status -ne 0 ]; then
    echo "$lifecycle_output" >&2
    echo "⚠  Could not apply lifecycle rule (continuing anyway). You can set it manually in the dashboard." >&2
  fi
else
  echo "  (no lifecycle.json — skipping)"
fi

echo "▶ Pushing secrets to Worker..."
npx wrangler secret bulk <<EOF
{
  "R2_ACCOUNT_ID": "${R2_ACCOUNT_ID}",
  "R2_BUCKET": "${R2_BUCKET}",
  "R2_ACCESS_KEY_ID": "${R2_ACCESS_KEY_ID}",
  "R2_SECRET_ACCESS_KEY": "${R2_SECRET_ACCESS_KEY}",
  "R2_PUB_HOST": "${R2_PUB_HOST}",
  "APP_SECRET": "${APP_SECRET}"
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
  echo "Workers.dev endpoint:"
  echo "  $worker_url/sign"
  echo
  echo "Once screencast.to is wired up as a custom domain, the canonical endpoint is:"
  echo "  https://screencast.to/sign"
  echo
  echo "Paste whichever you're using into screencast/Upload/Config.swift:"
  echo "  static let workerEndpoint = URL(string: \"https://screencast.to/sign\")!"
else
  echo "Could not auto-detect the Worker URL from output."
  echo "Look for the 'https://*.workers.dev' line above and paste it"
  echo "(with /sign appended) into screencast/Upload/Config.swift."
fi
echo
echo "If you haven't yet, enable Public Development URL on the bucket:"
echo "  Dashboard → R2 → $R2_BUCKET → Settings → Public Development URL → Enable"
echo "Then make sure R2_PUB_HOST in .env matches the pub-XXX.r2.dev host shown there."
