import assert from "node:assert/strict";
import test from "node:test";

import {
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";

import {
  handleEntitlement,
  verifyProductionThenSandbox,
} from "../src/api/entitlement";
import type { Env } from "../src/env";

function testEnv(): Env {
  return {
    UPLOAD_AUTH_MODE: "app-store",
    R2_ACCOUNT_ID: "unused",
    R2_BUCKET: "unused",
    R2_ACCESS_KEY_ID: "unused",
    R2_SECRET_ACCESS_KEY: "unused",
    R2_PUB_HOST: "media.example.test",
    APP_APPLE_ID: "1234567890",
    SERVICE_TOKEN_SECRET: "test-only-service-token-secret-that-is-long-enough",
    SIGN_LIMITER: { limit: async () => ({ success: true }) },
  };
}

test("entitlement rejects an invalid Apple-signed transaction without echoing it", async () => {
  const marker = "private-app-transaction-marker";
  const response = await handleEntitlement(
    new Request("https://share.example.test/entitlements/token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ appTransactionJWS: marker }),
    }),
    testEnv()
  );

  assert.equal(response.status, 401);
  assert.equal((await response.text()).includes(marker), false);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});

test("entitlement fails closed when the numeric App Store ID is absent", async () => {
  const env = testEnv();
  env.APP_APPLE_ID = "";
  const response = await handleEntitlement(
    new Request("https://share.example.test/entitlements/token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ appTransactionJWS: "not-a-jws" }),
    }),
    env
  );
  assert.equal(response.status, 503);
});

test("entitlement rejects non-object JSON without throwing", async () => {
  const response = await handleEntitlement(
    new Request("https://share.example.test/entitlements/token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "null",
    }),
    testEnv()
  );
  assert.equal(response.status, 400);
});

test("entitlement rejects an oversized JSON body before verification", async () => {
  const response = await handleEntitlement(
    new Request("https://share.example.test/entitlements/token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ appTransactionJWS: "x".repeat(37_000) }),
    }),
    testEnv()
  );
  assert.equal(response.status, 413);
});

test("entitlement reports transient Apple verification failures as retryable", async () => {
  const response = await handleEntitlement(
    new Request("https://share.example.test/entitlements/token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ appTransactionJWS: "opaque-proof" }),
    }),
    testEnv(),
    async () => {
      throw new VerificationException(VerificationStatus.RETRYABLE_VERIFICATION_FAILURE);
    }
  );

  assert.equal(response.status, 503);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.equal((await response.text()).includes("opaque-proof"), false);
});

test("production environment mismatch falls back to the Sandbox verifier", async () => {
  let sandboxCalls = 0;
  await verifyProductionThenSandbox(
    "opaque-proof",
    {
      verifyAndDecodeAppTransaction: async () => {
        throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
      },
    },
    {
      verifyAndDecodeAppTransaction: async () => {
        sandboxCalls += 1;
      },
    },
    VerificationStatus
  );
  assert.equal(sandboxCalls, 1);
});

test("production app-identifier mismatch falls back to the Sandbox verifier", async () => {
  let sandboxCalls = 0;
  await verifyProductionThenSandbox(
    "opaque-proof",
    {
      verifyAndDecodeAppTransaction: async () => {
        throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER);
      },
    },
    {
      verifyAndDecodeAppTransaction: async () => {
        sandboxCalls += 1;
      },
    },
    VerificationStatus
  );
  assert.equal(sandboxCalls, 1);
});

test("transient Production verification failure never falls through to Sandbox", async () => {
  const failure = new VerificationException(
    VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
  );
  let sandboxCalls = 0;

  await assert.rejects(
    verifyProductionThenSandbox(
      "opaque-proof",
      {
        verifyAndDecodeAppTransaction: async () => {
          throw failure;
        },
      },
      {
        verifyAndDecodeAppTransaction: async () => {
          sandboxCalls += 1;
        },
      },
      VerificationStatus
    ),
    (error) => error === failure
  );
  assert.equal(sandboxCalls, 0);
});
