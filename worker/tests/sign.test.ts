import assert from "node:assert/strict";
import test from "node:test";

import { handleSign } from "../src/api/sign";
import { issueServiceToken } from "../src/auth/service-token";
import type { Env } from "../src/env";

const serviceSecret = "test-only-service-token-secret-that-is-long-enough";

function testEnv(): Env {
  return {
    UPLOAD_AUTH_MODE: "app-store",
    R2_ACCOUNT_ID: "0123456789abcdef0123456789abcdef",
    R2_BUCKET: "test-recordings",
    R2_ACCESS_KEY_ID: "test-access-key",
    R2_SECRET_ACCESS_KEY: "test-secret-key",
    R2_PUB_HOST: "media.example.test",
    APP_APPLE_ID: "1234567890",
    SERVICE_TOKEN_SECRET: serviceSecret,
    MAX_UPLOAD_BYTES: "1048576",
    SIGN_LIMITER: { limit: async () => ({ success: true }) },
  };
}

test("sign rejects callers without an entitlement token", async () => {
  const response = await handleSign(
    new Request("https://share.example.test/sign", {
      method: "POST",
      body: JSON.stringify({ ext: "mov", sizeBytes: 20 }),
    }),
    testEnv()
  );
  assert.equal(response.status, 401);
});

test("official mode never accepts a configured self-hosted bypass token", async () => {
  const env = testEnv();
  env.SELF_HOSTED_UPLOAD_TOKEN = "private-static-token-that-is-long-enough";
  const response = await handleSign(
    new Request("https://share.example.test/sign", {
      method: "POST",
      headers: { Authorization: `Bearer ${env.SELF_HOSTED_UPLOAD_TOKEN}` },
      body: JSON.stringify({ ext: "mov", sizeBytes: 20 }),
    }),
    env
  );
  assert.equal(response.status, 401);
});

test("self-hosted mode accepts its explicitly configured static token", async () => {
  const env = testEnv();
  env.UPLOAD_AUTH_MODE = "self-hosted";
  env.SELF_HOSTED_UPLOAD_TOKEN = "private-static-token-that-is-long-enough";
  const response = await handleSign(
    new Request("https://private.example.test/sign", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.SELF_HOSTED_UPLOAD_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ext: "mov", sizeBytes: 20 }),
    }),
    env
  );
  assert.equal(response.status, 200);
});

test("self-hosted mode rejects a weak static token", async () => {
  const env = testEnv();
  env.UPLOAD_AUTH_MODE = "self-hosted";
  env.SELF_HOSTED_UPLOAD_TOKEN = "too-short";
  const response = await handleSign(
    new Request("https://private.example.test/sign", {
      method: "POST",
      headers: { Authorization: "Bearer too-short" },
      body: JSON.stringify({ ext: "mov", sizeBytes: 20 }),
    }),
    env
  );
  assert.equal(response.status, 401);
});

test("sign binds the declared byte length into the R2 signature", async () => {
  const { token } = await issueServiceToken(serviceSecret);
  const response = await handleSign(
    new Request("https://share.example.test/sign", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ext: "mov", sizeBytes: 20 }),
    }),
    testEnv()
  );

  assert.equal(response.status, 200);
  const body = await response.json() as {
    uploadUrl: string;
    requiredHeaders: Record<string, string>;
  };
  assert.equal(body.requiredHeaders["Content-Length"], "20");
  assert.equal(body.requiredHeaders["Content-Type"], "video/quicktime");
  assert.equal(body.requiredHeaders["Cache-Control"], "no-store");
  assert.match(
    decodeURIComponent(body.uploadUrl),
    /X-Amz-SignedHeaders=cache-control;content-length;content-type;host/i
  );
});

test("sign rejects a declared size above the configured limit", async () => {
  const { token } = await issueServiceToken(serviceSecret);
  const response = await handleSign(
    new Request("https://share.example.test/sign", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ext: "mov", sizeBytes: 1_048_577 }),
    }),
    testEnv()
  );
  assert.equal(response.status, 413);
});

test("sign rejects non-recording object types", async () => {
  const { token } = await issueServiceToken(serviceSecret);
  const response = await handleSign(
    new Request("https://share.example.test/sign", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ext: "html", sizeBytes: 20 }),
    }),
    testEnv()
  );
  assert.equal(response.status, 400);
});

test("sign rejects non-object JSON and non-string extensions", async () => {
  const { token } = await issueServiceToken(serviceSecret);
  for (const body of [null, { ext: 42, sizeBytes: 20 }]) {
    const response = await handleSign(
      new Request("https://share.example.test/sign", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      }),
      testEnv()
    );
    assert.equal(response.status, 400);
  }
});

test("sign rejects an oversized JSON body", async () => {
  const { token } = await issueServiceToken(serviceSecret);
  const response = await handleSign(
    new Request("https://share.example.test/sign", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ext: "mov", sizeBytes: 20, padding: "x".repeat(1_024) }),
    }),
    testEnv()
  );
  assert.equal(response.status, 413);
});
