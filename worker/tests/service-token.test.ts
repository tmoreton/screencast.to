import assert from "node:assert/strict";
import test from "node:test";

import { issueServiceToken, verifyServiceToken } from "../src/auth/service-token";

const secret = "test-only-service-token-secret-that-is-long-enough";

test("service tokens verify only during their short lifetime", async () => {
  const issued = await issueServiceToken(secret, 1_000);
  assert.equal(await verifyServiceToken(issued.token, secret, 1_001), true);
  assert.equal(await verifyServiceToken(issued.token, secret, issued.expiresAt), false);
  assert.equal(await verifyServiceToken(issued.token, `${secret}x`, 1_001), false);
});

test("service tokens contain no transaction or user identifier", async () => {
  const issued = await issueServiceToken(secret, 1_000);
  const payload = JSON.parse(Buffer.from(issued.token.split(".")[1]!, "base64url").toString("utf8"));
  assert.deepEqual(Object.keys(payload).sort(), ["aud", "exp", "iat", "nonce", "v"]);
});
