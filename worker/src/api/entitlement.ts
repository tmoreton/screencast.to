import type { SignedDataVerifier as SignedDataVerifierType } from "@apple/app-store-server-library";
import { APPLE_ROOT_CERTIFICATES } from "../apple-root-certificates";
import { issueServiceToken } from "../auth/service-token";
import type { Env } from "../env";
import { CORS } from "../views/shared";
import { readJSONBody } from "./request-body";

const APP_BUNDLE_ID = "to.screencast.app";
const MAX_JWS_LENGTH = 32_768;
const MAX_REQUEST_BYTES = 36 * 1_024;

let cachedProductionVerifier: SignedDataVerifierType | undefined;
let cachedSandboxVerifier: SignedDataVerifierType | undefined;
let cachedAppAppleId: number | undefined;
let cachedVerificationStatuses: VerificationStatuses | undefined;

interface EntitlementRequestBody {
  appTransactionJWS?: unknown;
}

interface TransactionVerifier {
  verifyAndDecodeAppTransaction(signedTransaction: string): Promise<unknown>;
}

export interface VerificationStatuses {
  RETRYABLE_VERIFICATION_FAILURE: number;
  INVALID_APP_IDENTIFIER: number;
  INVALID_ENVIRONMENT: number;
}

type VerifyTransaction = (signedTransaction: string, env: Env) => Promise<void>;

/**
 * Exchange an Apple-signed AppTransaction for a short-lived, anonymous upload
 * token. The decoded transaction and its identifiers are intentionally never
 * logged, returned, or persisted.
 */
export async function handleEntitlement(
  request: Request,
  env: Env,
  verifyTransaction: VerifyTransaction = verifyAppTransaction
): Promise<Response> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const { success } = await env.SIGN_LIMITER.limit({ key: `entitlement:${ip}` });
  if (!success) {
    return new Response("Too many requests", { status: 429, headers: CORS });
  }

  let verificationStatuses: VerificationStatuses;
  try {
    verificationStatuses = (await verifiersFor(env)).statuses;
    if (!env.SERVICE_TOKEN_SECRET || env.SERVICE_TOKEN_SECRET.length < 32) {
      throw new Error("Invalid SERVICE_TOKEN_SECRET configuration");
    }
  } catch {
    return new Response("Entitlement service is not configured", { status: 503, headers: CORS });
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
  const body = parsedBody.value as EntitlementRequestBody;

  const signedTransaction = body.appTransactionJWS;
  if (typeof signedTransaction !== "string" ||
      signedTransaction.length === 0 ||
      signedTransaction.length > MAX_JWS_LENGTH) {
    return new Response("Invalid request", { status: 400, headers: CORS });
  }

  try {
    await verifyTransaction(signedTransaction, env);
    const issued = await issueServiceToken(env.SERVICE_TOKEN_SECRET);
    return Response.json(
      { serviceToken: issued.token, expiresAt: issued.expiresAt },
      { headers: { "Cache-Control": "no-store", ...CORS } }
    );
  } catch (error) {
    const temporarilyUnavailable = verificationErrorStatus(error) ===
      verificationStatuses.RETRYABLE_VERIFICATION_FAILURE;
    return new Response(
      temporarilyUnavailable
        ? "Purchase verification is temporarily unavailable"
        : "Purchase could not be verified",
      {
      status: temporarilyUnavailable ? 503 : 401,
      headers: { "Cache-Control": "no-store", ...CORS },
      }
    );
  }
}

async function verifiersFor(env: Env): Promise<{
  production: SignedDataVerifierType;
  sandbox: SignedDataVerifierType;
  statuses: VerificationStatuses;
}> {
  const appAppleId = Number(env.APP_APPLE_ID);
  if (!Number.isSafeInteger(appAppleId) || appAppleId <= 0) {
    throw new Error("APP_APPLE_ID must be the numeric App Store app ID");
  }
  if (!cachedProductionVerifier || !cachedSandboxVerifier || !cachedVerificationStatuses ||
      cachedAppAppleId !== appAppleId) {
    // The official library's jsrsasign dependency initializes random state at
    // module evaluation time. Import it inside a request so Workers does not
    // reject that work as forbidden global-scope I/O.
    const { Environment, SignedDataVerifier, VerificationStatus } =
      await import("@apple/app-store-server-library");
    cachedProductionVerifier = new SignedDataVerifier(
      APPLE_ROOT_CERTIFICATES,
      true,
      Environment.PRODUCTION,
      APP_BUNDLE_ID,
      appAppleId
    );
    cachedSandboxVerifier = new SignedDataVerifier(
      APPLE_ROOT_CERTIFICATES,
      true,
      Environment.SANDBOX,
      APP_BUNDLE_ID
    );
    cachedAppAppleId = appAppleId;
    cachedVerificationStatuses = VerificationStatus;
  }
  return {
    production: cachedProductionVerifier,
    sandbox: cachedSandboxVerifier,
    statuses: cachedVerificationStatuses,
  };
}

async function verifyAppTransaction(signedTransaction: string, env: Env): Promise<void> {
  const verifiers = await verifiersFor(env);
  await verifyProductionThenSandbox(
    signedTransaction,
    verifiers.production,
    verifiers.sandbox,
    verifiers.statuses
  );
}

/**
 * Accept a Sandbox proof only when Production rejected the proof's environment
 * or app identifier. Signature, certificate, and transient OCSP failures must
 * never be reinterpreted as a Sandbox transaction.
 */
export async function verifyProductionThenSandbox(
  signedTransaction: string,
  production: TransactionVerifier,
  sandbox: TransactionVerifier,
  statuses: VerificationStatuses
): Promise<void> {
  try {
    await production.verifyAndDecodeAppTransaction(signedTransaction);
    return;
  } catch (error) {
    const status = verificationErrorStatus(error);
    if (status !== statuses.INVALID_ENVIRONMENT &&
        status !== statuses.INVALID_APP_IDENTIFIER) {
      throw error;
    }
    // App Review and TestFlight use Apple's sandbox even though the submitted
    // binary is production-signed. The sandbox verifier still requires an
    // Apple certificate chain, the exact bundle ID, and Sandbox receipt type;
    // Xcode/local StoreKit test JWS values are not accepted.
    await sandbox.verifyAndDecodeAppTransaction(signedTransaction);
  }
}

function verificationErrorStatus(error: unknown): number | undefined {
  if (typeof error !== "object" || error === null || !("status" in error)) {
    return undefined;
  }
  const status = (error as { status?: unknown }).status;
  return typeof status === "number" ? status : undefined;
}
