import type { Env } from "../env";

const TOKEN_AUDIENCE = "screencast-upload";
const TOKEN_TTL_SECONDS = 15 * 60;

interface ServiceTokenPayload {
  v: 1;
  aud: typeof TOKEN_AUDIENCE;
  iat: number;
  exp: number;
  nonce: string;
}

export interface IssuedServiceToken {
  token: string;
  expiresAt: number;
}

export async function issueServiceToken(
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000)
): Promise<IssuedServiceToken> {
  validateSecret(secret);
  const expiresAt = nowSeconds + TOKEN_TTL_SECONDS;
  const header = encodeJSON({ alg: "HS256", typ: "JWT" });
  const payload = encodeJSON({
    v: 1,
    aud: TOKEN_AUDIENCE,
    iat: nowSeconds,
    exp: expiresAt,
    nonce: crypto.randomUUID(),
  } satisfies ServiceTokenPayload);
  const unsigned = `${header}.${payload}`;
  const signature = await sign(unsigned, secret);
  return { token: `${unsigned}.${signature}`, expiresAt };
}

export async function verifyServiceToken(
  token: string,
  secret: string | undefined,
  nowSeconds = Math.floor(Date.now() / 1000)
): Promise<boolean> {
  if (!secret || secret.length < 32 || token.length > 4096) return false;
  const parts = token.split(".");
  if (parts.length !== 3) return false;

  const [header, payload, signature] = parts;
  const key = await importHmacKey(secret, ["verify"]);
  let signatureBytes: ArrayBuffer;
  try {
    signatureBytes = decodeBase64URL(signature);
  } catch {
    return false;
  }
  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    signatureBytes,
    new TextEncoder().encode(`${header}.${payload}`)
  );
  if (!valid) return false;

  try {
    const decoded = JSON.parse(new TextDecoder().decode(decodeBase64URL(payload))) as Partial<ServiceTokenPayload>;
    return decoded.v === 1 &&
      decoded.aud === TOKEN_AUDIENCE &&
      Number.isInteger(decoded.iat) &&
      Number.isInteger(decoded.exp) &&
      typeof decoded.nonce === "string" &&
      decoded.nonce.length >= 16 &&
      decoded.iat! <= nowSeconds + 60 &&
      decoded.exp! > nowSeconds &&
      decoded.exp! - decoded.iat! === TOKEN_TTL_SECONDS;
  } catch {
    return false;
  }
}

export async function authorizeUpload(request: Request, env: Env): Promise<boolean> {
  const token = bearerToken(request);
  if (!token) return false;
  if (env.UPLOAD_AUTH_MODE === "app-store") {
    return verifyServiceToken(token, env.SERVICE_TOKEN_SECRET);
  }
  if (env.UPLOAD_AUTH_MODE === "self-hosted") {
    return Boolean(
      env.SELF_HOSTED_UPLOAD_TOKEN &&
      env.SELF_HOSTED_UPLOAD_TOKEN.length >= 32 &&
      timingSafeEqual(token, env.SELF_HOSTED_UPLOAD_TOKEN)
    );
  }
  return false;
}

function bearerToken(request: Request): string | undefined {
  const value = request.headers.get("Authorization") ?? "";
  const match = /^Bearer ([^\s]+)$/i.exec(value);
  return match?.[1];
}

function validateSecret(secret: string): void {
  if (secret.length < 32) {
    throw new Error("SERVICE_TOKEN_SECRET must contain at least 32 characters");
  }
}

async function sign(value: string, secret: string): Promise<string> {
  const key = await importHmacKey(secret, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return encodeBase64URL(new Uint8Array(signature));
}

function importHmacKey(secret: string, usages: KeyUsage[]): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usages
  );
}

function encodeJSON(value: object): string {
  return encodeBase64URL(new TextEncoder().encode(JSON.stringify(value)));
}

function encodeBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeBase64URL(value: string): ArrayBuffer {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("Invalid base64url");
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0)).buffer as ArrayBuffer;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
