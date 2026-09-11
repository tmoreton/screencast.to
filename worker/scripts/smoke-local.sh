#!/usr/bin/env bash
set -euo pipefail

smoke_port="${WORKER_SMOKE_PORT:-8793}"
smoke_base_url="http://127.0.0.1:${smoke_port}"
smoke_tmp_dir="$(mktemp -d)"
smoke_log="$smoke_tmp_dir/wrangler.log"
worker_pid=""

cleanup() {
  if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
    kill "$worker_pid" 2>/dev/null || true
    wait "$worker_pid" 2>/dev/null || true
  fi
  rm -r "$smoke_tmp_dir"
}
trap cleanup EXIT

CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV=false npx wrangler dev \
  --local \
  --ip 127.0.0.1 \
  --port "$smoke_port" \
  --log-level error \
  --var UPLOAD_AUTH_MODE:app-store \
  --var R2_ACCOUNT_ID:0123456789abcdef0123456789abcdef \
  --var R2_BUCKET:test-recordings \
  --var R2_ACCESS_KEY_ID:test-access-key \
  --var R2_SECRET_ACCESS_KEY:test-secret-key \
  --var R2_PUB_HOST:media.example.test \
  --var APP_APPLE_ID:1234567890 \
  --var SERVICE_TOKEN_SECRET:test-only-service-token-secret-that-is-long-enough \
  --var MAX_UPLOAD_BYTES:1048576 \
  >"$smoke_log" 2>&1 &
worker_pid=$!

ready=false
for _ in {1..80}; do
  if curl -fsS -o /dev/null "$smoke_base_url/" 2>/dev/null; then
    ready=true
    break
  fi
  if ! kill -0 "$worker_pid" 2>/dev/null; then
    echo "Worker exited before becoming ready." >&2
    sed -n '1,160p' "$smoke_log" >&2
    exit 1
  fi
  sleep 0.25
done
if [[ "$ready" != true ]]; then
  echo "Worker did not become ready." >&2
  sed -n '1,160p' "$smoke_log" >&2
  exit 1
fi

privacy_status="$(curl -sS -o /dev/null -w '%{http_code}' "$smoke_base_url/privacy")"
support_status="$(curl -sS -o /dev/null -w '%{http_code}' "$smoke_base_url/support")"
website_image_status="$(curl -sS -o /dev/null -w '%{http_code}' "$smoke_base_url/assets/website.png")"
app_icon_status="$(curl -sS -o /dev/null -w '%{http_code}' "$smoke_base_url/assets/icon.png")"
licenses_status="$(curl -sS -o "$smoke_tmp_dir/third-party-licenses.txt" -w '%{http_code}' \
  "$smoke_base_url/third-party-licenses.txt")"
curl -sS -D "$smoke_tmp_dir/viewer-headers.txt" -o /dev/null \
  "$smoke_base_url/v/Abc123.mov"
sign_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  --data '{"ext":"mov","sizeBytes":20}' "$smoke_base_url/sign")"
entitlement_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  --data '{"appTransactionJWS":"not-a-jws"}' "$smoke_base_url/entitlements/token")"
oversized_status="$(node -e 'process.stdout.write(JSON.stringify({appTransactionJWS:"x".repeat(37000)}))' |
  curl -sS -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' --data-binary @- \
    "$smoke_base_url/entitlements/token")"

[[ "$privacy_status" == 200 ]]
[[ "$support_status" == 200 ]]
[[ "$website_image_status" == 200 ]]
[[ "$app_icon_status" == 200 ]]
[[ "$licenses_status" == 200 ]]
cmp -s THIRD_PARTY_LICENSES.txt "$smoke_tmp_dir/third-party-licenses.txt"
grep -Eqi '^referrer-policy: no-referrer' "$smoke_tmp_dir/viewer-headers.txt"
[[ "$sign_status" == 401 ]]
[[ "$entitlement_status" == 401 ]]
[[ "$oversized_status" == 413 ]]

echo "Worker runtime smoke passed (pages/assets/notices 200, private viewer referrer blocked, auth failures 401, oversized body 413)."
