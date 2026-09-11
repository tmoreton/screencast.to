import { AwsClient } from "aws4fetch";
import { authorizeUpload } from "../auth/service-token";
import type { Env } from "../env";
import { CORS } from "../views/shared";
import { readJSONBody } from "./request-body";

interface SignRequestBody {
  ext?: string;
  sizeBytes?: number;
}

const DEFAULT_MAX_UPLOAD_BYTES = 1_073_741_824; // 1 GiB
const MAX_REQUEST_BYTES = 1_024;

/** POST /sign — mint a 15-minute, size-bound presigned PUT URL. */
export async function handleSign(request: Request, env: Env): Promise<Response> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const { success } = await env.SIGN_LIMITER.limit({ key: `sign:${ip}` });
  if (!success) {
    return new Response("Too many requests", { status: 429, headers: CORS });
  }

  if (!await authorizeUpload(request, env)) {
    return new Response("Unauthorized", { status: 401, headers: CORS });
  }

  const parsedBody = await readJSONBody(request, MAX_REQUEST_BYTES);
  if (!parsedBody.ok) {
    return new Response(
      parsedBody.status === 413 ? "Request too large" : "Invalid request",
      { status: parsedBody.status, headers: CORS }
    );
  }
  if (parsedBody.value === null || typeof parsedBody.value !== "object" || Array.isArray(parsedBody.value)) {
    return new Response("Invalid request", { status: 400, headers: CORS });
  }
  const body = parsedBody.value as SignRequestBody;

  const sizeBytes = body.sizeBytes;
  const maxUploadBytes = parseMaxUploadBytes(env.MAX_UPLOAD_BYTES);
  if (typeof sizeBytes !== "number" || !Number.isSafeInteger(sizeBytes) || sizeBytes <= 0) {
    return new Response("Missing recording size", { status: 400, headers: CORS });
  }
  if (sizeBytes > maxUploadBytes) {
    return new Response("Recording too large", { status: 413, headers: CORS });
  }

  if (body.ext !== undefined &&
      (typeof body.ext !== "string" || body.ext.toLowerCase() !== "mov")) {
    return new Response("Unsupported recording type", { status: 400, headers: CORS });
  }
  const ext = "mov";
  const id = generateShortId();
  const key = `recordings/${id}.${ext}`;
  const contentLength = String(sizeBytes);
  const contentType = "video/quicktime";
  const cacheControl = "no-store";

  const r2 = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
  });

  const endpoint = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET}/${key}`;
  const signed = await r2.sign(
    new Request(`${endpoint}?X-Amz-Expires=900`, {
      method: "PUT",
      headers: {
        "Cache-Control": cacheControl,
        "Content-Length": contentLength,
        "Content-Type": contentType,
      },
    }),
    { aws: { signQuery: true, allHeaders: true } }
  );

  const origin = new URL(request.url).origin;
  const publicUrl = `${origin}/v/${id}.${ext}`;

  return Response.json(
    {
      uploadUrl: signed.url,
      publicUrl,
      requiredHeaders: {
        "Cache-Control": cacheControl,
        "Content-Length": contentLength,
        "Content-Type": contentType,
      },
    },
    { headers: { "Cache-Control": "no-store", ...CORS } }
  );
}

export function parseMaxUploadBytes(value: string | undefined): number {
  if (!value) return DEFAULT_MAX_UPLOAD_BYTES;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) return DEFAULT_MAX_UPLOAD_BYTES;
  return parsed;
}

function generateShortId(): string {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = new Uint8Array(10);
  crypto.getRandomValues(bytes);
  let out = "";
  for (const byte of bytes) out += alphabet[byte % 62];
  return out;
}
