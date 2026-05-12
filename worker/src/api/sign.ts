import { AwsClient } from "aws4fetch";
import type { Env } from "../env";
import { CORS } from "../views/shared";

interface SignRequestBody {
  ext?: string;
}

/**
 * POST /sign — mints a 15-minute presigned PUT URL for a new recording.
 * Authenticated via shared secret (`X-Screencast-Auth`) and per-IP rate
 * limited at 10/min via Cloudflare's rate-limit binding.
 */
export async function handleSign(request: Request, env: Env): Promise<Response> {
  // Shared-secret auth.
  const provided = request.headers.get("X-Screencast-Auth") ?? "";
  if (!env.APP_SECRET || !timingSafeEqual(provided, env.APP_SECRET)) {
    return new Response("Unauthorized", { status: 401, headers: CORS });
  }

  // Per-IP rate limit.
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const { success } = await env.SIGN_LIMITER.limit({ key: ip });
  if (!success) {
    return new Response("Too many requests", { status: 429, headers: CORS });
  }

  let body: SignRequestBody = {};
  try {
    body = (await request.json()) as SignRequestBody;
  } catch {
    // empty body OK
  }
  const ext = sanitizeExt(body.ext ?? "mov");
  const id = generateShortId();
  const key = `recordings/${id}.${ext}`;

  const r2 = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
  });

  const endpoint = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET}/${key}`;
  const signed = await r2.sign(
    new Request(`${endpoint}?X-Amz-Expires=900`, { method: "PUT" }),
    { aws: { signQuery: true } }
  );

  const origin = new URL(request.url).origin;
  const publicUrl = `${origin}/v/${id}.${ext}`;

  return new Response(
    JSON.stringify({ uploadUrl: signed.url, publicUrl }),
    { status: 200, headers: { "Content-Type": "application/json", ...CORS } }
  );
}

function sanitizeExt(ext: string): string {
  return ext.replace(/[^a-zA-Z0-9]/g, "").slice(0, 8) || "mov";
}

// 10-char URL-safe random ID. 62^10 ≈ 8.4 × 10^17 combinations — collision
// risk is negligible for 24h-lifetime recordings.
function generateShortId(): string {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = new Uint8Array(10);
  crypto.getRandomValues(bytes);
  let out = "";
  for (const b of bytes) out += alphabet[b % 62];
  return out;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
