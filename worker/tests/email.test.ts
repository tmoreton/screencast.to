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
    PURCHASE_EMAIL_ENABLED: "true",
    PURCHASE_EMAIL: { async send() { throw new Error("Email delivery must be mocked explicitly."); } },
    PURCHASE_EMAIL_FROM: "purchases@screencast.to",
    PURCHASE_EMAIL_REPLY_TO: "support@screencast.to",
    ...changes,
  } as unknown as Env;
}

test("purchase recovery requires an explicit enable gate, native binding, and valid sender", () => {
  assert.equal(isPurchaseEmailConfigured(fakeEnv()), true);
  assert.equal(isPurchaseEmailConfigured(fakeEnv({ PURCHASE_EMAIL_REPLY_TO: undefined })), true);
  for (const changes of [
    { PURCHASE_EMAIL_ENABLED: undefined },
    { PURCHASE_EMAIL_ENABLED: "false" },
    { PURCHASE_EMAIL_ENABLED: "TRUE" },
    { PURCHASE_EMAIL: undefined },
    { PURCHASE_EMAIL: {} },
    { PURCHASE_EMAIL_FROM: undefined },
    { PURCHASE_EMAIL_FROM: "invalid" },
    { PURCHASE_EMAIL_FROM: "Screencast.to <purchases@screencast.to>" },
    { PURCHASE_EMAIL_FROM: "purchases@screencast.to\r\nBcc: another@example.com" },
    { PURCHASE_EMAIL_REPLY_TO: "invalid" },
  ]) assert.equal(isPurchaseEmailConfigured(fakeEnv(changes)), false);
  assert.equal(isPurchaseEmailConfigured(fakeEnv({ PURCHASE_EMAIL: undefined, RESEND_API_KEY: "unused-legacy-key" })), false);
});

test("restore delivery uses the Cloudflare binding with a named sender and exact private link", async (t) => {
  // No HTTP provider fallback is allowed, even if a stale credential is present.
  t.mock.method(globalThis, "fetch", async () => { throw new Error("must not use an external email API"); });
  const calls: EmailMessageBuilder[] = [];
  const env = fakeEnv({
    RESEND_API_KEY: "unused-legacy-key",
    PURCHASE_EMAIL: { async send(message: EmailMessageBuilder) {
      calls.push(message);
      return { messageId: "mock_message_id" };
    } },
  });
  await sendPurchaseRestoreEmail(env, "buyer@example.com", restoreURL);
  assert.equal(calls.length, 1);
  const message = calls[0];
  assert.deepEqual(message.from, { email: "purchases@screencast.to", name: "Screencast.to" });
  assert.deepEqual(message.to, ["buyer@example.com"]);
  assert.equal(message.replyTo, "support@screencast.to");
  assert.equal(message.subject, "Connect sharing in Screencast.to");
  assert.ok(message.text?.includes(restoreURL));
  assert.ok(message.html?.includes(restoreURL.replaceAll("&", "&amp;")));
  assert.match(message.text!, /If you did not request this email, you can ignore it/);
  assert.equal(message.bcc, undefined);
  assert.equal(message.cc, undefined);
  assert.equal(message.headers, undefined);
});

test("recovery without an app connection accepts the restore token alone", async () => {
  let message: EmailMessageBuilder | undefined;
  const env = fakeEnv({ PURCHASE_EMAIL: { async send(value: EmailMessageBuilder) {
    message = value;
    return { messageId: "mock_message_id" };
  } } });
  const link = `https://screencast.to/connect-sharing.html?restore=${restoreToken}`;
  await sendPurchaseRestoreEmail(env, "buyer@example.com", link);
  assert.ok(message?.text?.includes(link));
});

test("invalid inputs and disabled recovery never call the native email binding", async () => {
  let calls = 0;
  const binding = { async send() {
    calls += 1;
    throw new Error("must not send");
  } };
  const env = fakeEnv({ PURCHASE_EMAIL: binding });
  for (const recipient of ["invalid", "buyer@example.com\r\nBcc: another@example.com", "one@example.com,two@example.com"]) {
    await assert.rejects(sendPurchaseRestoreEmail(env, recipient, restoreURL), /Invalid purchase email recipient/);
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
  ]) await assert.rejects(sendPurchaseRestoreEmail(env, "buyer@example.com", invalidURL), /Invalid purchase restore URL/);
  for (const changes of [{ PURCHASE_EMAIL_ENABLED: "false" }, { PURCHASE_EMAIL: undefined }]) {
    await assert.rejects(sendPurchaseRestoreEmail(fakeEnv({ PURCHASE_EMAIL: binding, ...changes }), "buyer@example.com", restoreURL), /not configured/);
  }
  assert.equal(calls, 0);
});

test("native email errors and invalid acknowledgements never expose private delivery data", async () => {
  const sensitive = `buyer@example.com ${restoreURL}`;
  const cases = [
    async () => { throw Object.assign(new Error(sensitive), { code: "E_SENDER_NOT_VERIFIED" }); },
    async () => { throw Object.assign(new Error(sensitive), { code: "E_DAILY_LIMIT_EXCEEDED" }); },
    async () => null,
    async () => ({}),
    async () => ({ messageId: "" }),
  ];
  for (const send of cases) {
    await assert.rejects(sendPurchaseRestoreEmail(fakeEnv({ PURCHASE_EMAIL: { send } }), "buyer@example.com", restoreURL), (error: Error) => {
      assert.equal(error.message, "Purchase restore email could not be sent.");
      assert.equal(error.cause, undefined);
      return true;
    });
  }
});
