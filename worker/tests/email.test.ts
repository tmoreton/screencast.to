import assert from "node:assert/strict";
import test from "node:test";
import { isPurchaseEmailConfigured, sendPurchaseRestoreEmail } from "../src/email";
import type { Env } from "../src/env";

const restoreToken = "r".repeat(43);
const challenge = "c".repeat(43);
const state = "s".repeat(43);
const restoreURL = `https://screencast.to/connect-sharing.html?restore=${restoreToken}&code_challenge=${challenge}&state=${state}`;

function fakeEnv(changes: Record<string, unknown> = {}): Env {
  return {
    RESEND_API_KEY: "re_test_only_not_a_real_key",
    PURCHASE_EMAIL_FROM: "Screencast.to <downloads@yaprflow.com>",
    PURCHASE_EMAIL_REPLY_TO: "support@screencast.to",
    ...changes,
  } as unknown as Env;
}

test("purchase email requires the existing provider credential and a valid configured sender", () => {
  assert.equal(isPurchaseEmailConfigured(fakeEnv()), true);
  assert.equal(isPurchaseEmailConfigured(fakeEnv({ PURCHASE_EMAIL_REPLY_TO: undefined })), true);
  assert.equal(isPurchaseEmailConfigured(fakeEnv({ PURCHASE_EMAIL_FROM: "downloads@yaprflow.com" })), true);
  for (const changes of [
    { RESEND_API_KEY: undefined },
    { RESEND_API_KEY: "wrong-provider-key" },
    { PURCHASE_EMAIL_FROM: undefined },
    { PURCHASE_EMAIL_FROM: "invalid" },
    { PURCHASE_EMAIL_FROM: "Screencast.to <downloads@yaprflow.com>\r\nBcc: another@example.com" },
    { PURCHASE_EMAIL_REPLY_TO: "invalid" },
  ]) assert.equal(isPurchaseEmailConfigured(fakeEnv(changes)), false);
});

test("restore delivery uses only Resend email sending and preserves the private restore link", async (t) => {
  const calls: { target: unknown; options: RequestInit | undefined }[] = [];
  t.mock.method(globalThis, "fetch", async (target: unknown, options?: RequestInit) => {
    calls.push({ target, options });
    return Response.json({ id: "mock_message_id" });
  });
  await sendPurchaseRestoreEmail(fakeEnv(), "buyer@example.com", restoreURL);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].target, "https://api.resend.com/emails");
  assert.equal(calls[0].options?.method, "POST");
  assert.equal(calls[0].options?.redirect, "error");
  assert.ok(calls[0].options?.signal instanceof AbortSignal);
  const headers = new Headers(calls[0].options?.headers);
  assert.equal(headers.get("Authorization"), "Bearer re_test_only_not_a_real_key");
  assert.equal(headers.get("Content-Type"), "application/json");
  const body = JSON.parse(String(calls[0].options?.body));
  assert.equal(body.from, "Screencast.to <downloads@yaprflow.com>");
  assert.deepEqual(body.to, ["buyer@example.com"]);
  assert.equal(body.reply_to, "support@screencast.to");
  assert.equal(body.subject, "Connect sharing in Screencast.to");
  assert.ok(body.text.includes(restoreURL));
  assert.ok(body.html.includes(restoreURL.replaceAll("&", "&amp;")));
  assert.match(body.text, /If you did not request this email, you can ignore it/);
  assert.equal(body.bcc, undefined);
  assert.equal(body.cc, undefined);
  assert.match(headers.get("Idempotency-Key")!, /^screencast-restore\/[a-f0-9]{64}$/);
});

test("identical restore requests are idempotent and different links have different request IDs", async (t) => {
  const keys: (string | null)[] = [];
  t.mock.method(globalThis, "fetch", async (_target: unknown, options?: RequestInit) => {
    keys.push(new Headers(options?.headers).get("Idempotency-Key"));
    return Response.json({ id: "mock_message_id" });
  });
  await sendPurchaseRestoreEmail(fakeEnv(), "buyer@example.com", restoreURL);
  await sendPurchaseRestoreEmail(fakeEnv(), "buyer@example.com", restoreURL);
  await sendPurchaseRestoreEmail(fakeEnv(), "buyer@example.com", restoreURL.replace(restoreToken, "q".repeat(43)));
  assert.equal(keys[0], keys[1]);
  assert.notEqual(keys[0], keys[2]);
  assert.ok(keys.every((key) => !key!.includes("buyer") && !key!.includes(restoreToken)));
});

test("recovery without an app connection accepts the restore token alone", async (t) => {
  let body: { text: string } | undefined;
  t.mock.method(globalThis, "fetch", async (_target: unknown, options?: RequestInit) => {
    body = JSON.parse(String(options?.body));
    return Response.json({ id: "mock_message_id" });
  });
  const link = `https://screencast.to/connect-sharing.html?restore=${restoreToken}`;
  await sendPurchaseRestoreEmail(fakeEnv(), "buyer@example.com", link);
  assert.ok(body?.text.includes(link));
});

test("invalid recipients and off-site or malformed restore links never contact the email provider", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => {
    calls += 1;
    throw new Error("must not send");
  });
  for (const recipient of ["invalid", "buyer@example.com\r\nBcc: another@example.com", "one@example.com,two@example.com"]) {
    await assert.rejects(sendPurchaseRestoreEmail(fakeEnv(), recipient, restoreURL), /Invalid purchase email recipient/);
  }
  for (const invalidURL of [
    restoreURL.replace("https:", "http:"),
    restoreURL.replace("screencast.to", "other.example"),
    restoreURL.replace("https://", "https://user:password@"),
    restoreURL.replace("connect-sharing.html", "confirmation.html"),
    restoreURL + "#private-data",
    restoreURL + "&next=https://other.example",
    restoreURL + "&restore=duplicate-proof",
    restoreURL.replace(restoreToken, "short"),
    restoreURL.replace(challenge, "short"),
    restoreURL.replace(state, "short"),
    restoreURL.replace(`&state=${state}`, ""),
    restoreURL.replace(`&code_challenge=${challenge}`, ""),
    "https://screencast.to/connect-sharing.html?restore=proof",
    "not a URL",
  ]) await assert.rejects(sendPurchaseRestoreEmail(fakeEnv(), "buyer@example.com", invalidURL), /Invalid purchase restore URL/);
  await assert.rejects(sendPurchaseRestoreEmail(fakeEnv({ RESEND_API_KEY: undefined }), "buyer@example.com", restoreURL), /not configured/);
  assert.equal(calls, 0);
});

test("email-provider failures never expose provider bodies, addresses, or restore credentials", async (t) => {
  const sensitive = `buyer@example.com ${restoreURL} re_test_only_not_a_real_key`;
  for (const response of [
    new Response(sensitive, { status: 403 }),
    new Response(sensitive, { status: 429 }),
    new Response(sensitive, { status: 500 }),
    new Response(sensitive, { status: 200 }),
    Response.json({ message: sensitive }),
    Response.json({ id: "" }),
  ]) {
    const fetch = t.mock.method(globalThis, "fetch", async () => response);
    await assert.rejects(sendPurchaseRestoreEmail(fakeEnv(), "buyer@example.com", restoreURL), (error: Error) => {
      assert.equal(error.message, "Purchase restore email could not be sent.");
      assert.equal(error.cause, undefined);
      return true;
    });
    fetch.mock.restore();
  }
  t.mock.method(globalThis, "fetch", async () => { throw new Error(sensitive); });
  await assert.rejects(sendPurchaseRestoreEmail(fakeEnv(), "buyer@example.com", restoreURL), (error: Error) => {
    assert.equal(error.message, "Purchase restore email could not be sent.");
    assert.equal(error.cause, undefined);
    return true;
  });
});
