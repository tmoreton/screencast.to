import assert from "node:assert/strict";
import test from "node:test";
import { handleWebsiteSharing } from "../src/api/website-sharing";
import { verifyServiceToken } from "../src/auth/service-token";
import type { Env } from "../src/env";

const verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
const challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
const state = "s".repeat(43);
const sessionID = "cs_test_1234567890123456";
const complimentaryCoupon = "ScreencastComplimentaryTest";
function fixture() {
  const objects = new Map<string, { value: string; etag: string; customMetadata?: Record<string, string> }>();
  let revision = 0;
  const env = {
    UPLOAD_AUTH_MODE: "app-store", SERVICE_TOKEN_SECRET: "private-test-secret-at-least-thirty-two-characters",
    CHECKOUT_BASE_URL: "https://screencast.to", STRIPE_SECRET_KEY: "sk_test_1234567890", STRIPE_PRICE_ID: "price_valid",
    PURCHASE_EMAIL: { async send() { return { messageId: "test-only" }; } },
    PURCHASE_EMAIL_ENABLED: "true", PURCHASE_EMAIL_FROM: "purchases@screencast.to",
    SIGN_LIMITER: { async limit() { return { success: true }; } },
    RELEASES: {
      async get(key: string) { const o = objects.get(key); return o ? { ...o, async json() { return JSON.parse(o.value); } } : null; },
      async put(key: string, value: string, options?: R2PutOptions) {
        const condition = options?.onlyIf as R2Conditional | undefined;
        if (condition?.etagMatches && objects.get(key)?.etag !== condition.etagMatches) return null;
        if (condition?.etagDoesNotMatch === "*" && objects.has(key)) return null;
        const o = { value, etag: String(++revision), customMetadata: options?.customMetadata };
        objects.set(key, o); return o;
      },
      async delete(keys: string | string[]) { for (const key of Array.isArray(keys) ? keys : [keys]) objects.delete(key); },
      async list() { return { objects: [...objects].map(([key, o]) => ({ key, customMetadata: o.customMetadata })) }; },
    },
  } as unknown as Env;
  const session: any = { id: sessionID, mode: "payment", livemode: false, status: "complete", payment_status: "paid",
    payment_intent: "pi_valid", metadata: { product: "screencast-mac" }, customer_details: { email: "buyer@example.com" },
    line_items: { has_more: false, data: [{ quantity: 1, price: { id: "price_valid" } }] } };
  const charge: any = { paid: true, captured: true, status: "succeeded", amount_refunded: 0, refunded: false, disputed: false, livemode: false };
  const intent: any = { status: "succeeded", livemode: false, latest_charge: charge };
  const customerPage = { data: [{ id: "cus_buyer", email: "buyer@example.com" }], has_more: false,
    async *[Symbol.asyncIterator]() { yield* this.data; } };
  const sessionPage = { data: [session], has_more: false, async *[Symbol.asyncIterator]() { yield* this.data; } };
  const stripe: any = {
    checkout: { sessions: { async retrieve() { return session; }, list() { return sessionPage; } } },
    paymentIntents: { async retrieve() { return intent; } },
    customers: { list() { return customerPage; }, search() { return customerPage; } },
  };
  const sent: { to: string; url: string }[] = [];
  let now = Math.floor(Date.now() / 1000);
  const dependencies = { stripeFactory: () => stripe, now: () => now,
    async sendEmail(_env: Env, to: string, url: string) { sent.push({ to, url }); }, logger: { error() {} } };
  const request = (route: string, body?: unknown, headers: Record<string, string> = {}) => new Request(`https://screencast.to/api/sharing/${route}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { Origin: "https://screencast.to", Cookie: `__Host-screencast-purchase=${sessionID}`, "Content-Type": "application/json", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const call = async (route: string, body?: unknown, headers?: Record<string, string>) => (await handleWebsiteSharing(request(route, body, headers), env, dependencies))!;
  const authorize = async () => {
    const r = await call("authorize", { codeChallenge: challenge, state }); assert.equal(r.status, 200);
    const url = new URL((await r.json() as any).callbackURL);
    assert.equal(url.origin, "null"); assert.equal(url.host, "sharing");
    return url.searchParams.get("code")!;
  };
  return { env, objects, session, charge, intent, stripe, sent, request, dependencies, call, authorize, advance(seconds: number) { now += seconds; } };
}

function complimentaryFixture() {
  const f = fixture();
  f.env.STRIPE_COMPLIMENTARY_COUPON_ID = complimentaryCoupon;
  Object.assign(f.session, { payment_status: "no_payment_required", payment_intent: null,
    amount_total: 0, amount_subtotal: 2900, total_details: { amount_discount: 2900 },
    discounts: [{ coupon: complimentaryCoupon, promotion_code: null }] });
  return f;
}

test("paid website purchase connects through PKCE, issues valid15minute token and renewable opaque grant", async () => {
  const f = fixture();
  const status = await f.call("status"); assert.deepEqual(await status.json(), { paid: true, mode: "test", recoveryAvailable: true });
  const code = await f.authorize();
  const exchanged = await f.call("exchange", { code, codeVerifier: verifier, state }); assert.equal(exchanged.status, 200);
  const auth = await exchanged.json() as any;
  assert.equal(await verifyServiceToken(auth.serviceToken, f.env.SERVICE_TOKEN_SECRET), true);
  assert.equal(auth.sharingGrant.includes(sessionID), false);
  assert.equal(exchanged.headers.get("Cache-Control"), "private, no-store, max-age=0");
  f.advance(16 * 60);
  const renewed = await f.call("token", { sharingGrant: auth.sharingGrant }); assert.equal(renewed.status, 200);
  assert.notEqual((await renewed.json() as any).sharingGrant, auth.sharingGrant);
  assert.equal((await f.call("exchange", { code, codeVerifier: verifier, state })).status, 401);
});
test("invalid PKCE or state cannot consume a code, concurrent redemption succeeds once", async () => {
  const f = fixture(), code = await f.authorize();
  assert.equal((await f.call("exchange", { code, codeVerifier: "a".repeat(43), state })).status, 401);
  assert.equal((await f.call("exchange", { code, codeVerifier: verifier, state: "x".repeat(43) })).status, 401);
  const results = await Promise.all([f.call("exchange", { code, codeVerifier: verifier, state }), f.call("exchange", { code, codeVerifier: verifier, state })]);
  assert.deepEqual(results.map(r => r.status).sort(), [200, 401]);
});
test("expired codes and grants, tampered grants and wrong Stripe mode are denied", async () => {
  const f = fixture(), code = await f.authorize(); f.advance(901);
  assert.equal((await f.call("exchange", { code, codeVerifier: verifier, state })).status, 401);
  const fresh = await f.authorize();
  const auth = await (await f.call("exchange", { code: fresh, codeVerifier: verifier, state })).json() as any;
  assert.equal((await f.call("token", { sharingGrant: auth.sharingGrant.slice(0, -3) + "aaa" })).status, 401);
  f.env.STRIPE_SECRET_KEY = "sk_live_1234567890";
  assert.equal((await f.call("token", { sharingGrant: auth.sharingGrant })).status, 401);
  f.env.STRIPE_SECRET_KEY = "sk_test_1234567890"; f.advance(366 * 86400);
  assert.equal((await f.call("token", { sharingGrant: auth.sharingGrant })).status, 401);
});
test("only allowlisted complete paid purchases with settled unrefunded undisputed charges connect", async () => {
  for (const mutate of [
    (f: any) => f.session.status = "open", (f: any) => f.session.payment_status = "unpaid",
    (f: any) => f.session.livemode = true, (f: any) => f.session.metadata.product = "other",
    (f: any) => f.session.line_items.data[0].price.id = "price_other",
    (f: any) => f.session.line_items.data[0].quantity = 2, (f: any) => f.charge.refunded = true,
    (f: any) => f.charge.amount_refunded = 1, (f: any) => f.charge.disputed = true,
    (f: any) => f.charge.captured = false, (f: any) => f.intent.status = "processing",
  ]) {
    const f = fixture(); mutate(f);
    assert.equal((await f.call("authorize", { codeChallenge: challenge, state })).status, 401);
  }
});
test("a refund revokes an already connected purchase at next token renewal", async () => {
  const f = fixture(), code = await f.authorize();
  const auth = await (await f.call("exchange", { code, codeVerifier: verifier, state })).json() as any;
  f.charge.amount_refunded = 100;
  assert.equal((await f.call("token", { sharingGrant: auth.sharingGrant })).status, 401);
});
test("an approved complimentary order recovers by email and connects without a PaymentIntent", async () => {
  const f = complimentaryFixture();
  let intentReads = 0;
  f.stripe.paymentIntents.retrieve = async () => { intentReads += 1; throw new Error("A no-cost order has no PaymentIntent"); };
  const initial = await f.call("status", undefined, { Cookie: "" });
  assert.deepEqual(await initial.json(), { paid: false, mode: "test", recoveryAvailable: true });
  const recovered = await f.call("restore", { email: "buyer@example.com", codeChallenge: challenge, state }, { Cookie: "" });
  assert.equal(recovered.status, 200);
  assert.deepEqual(await recovered.json(), { sent: true });
  assert.equal(f.sent.length, 1);
  assert.equal(f.sent[0].to, "buyer@example.com");
  const link = new URL(f.sent[0].url);
  assert.equal(link.searchParams.get("state"), state);
  assert.equal(link.searchParams.get("code_challenge"), challenge);
  const token = link.searchParams.get("restore");
  const restored = await f.call("restore/complete", { token }, { Cookie: "" });
  assert.equal(restored.status, 200);
  const cookie = restored.headers.get("Set-Cookie")?.split(";")[0];
  assert.equal(cookie, `__Host-screencast-purchase=${sessionID}`);
  const authorized = await f.call("authorize", { codeChallenge: challenge, state }, { Cookie: cookie! });
  assert.equal(authorized.status, 200);
  const callback = new URL((await authorized.json() as any).callbackURL);
  assert.equal(callback.searchParams.get("state"), state);
  const code = callback.searchParams.get("code");
  const exchanged = await f.call("exchange", { code, codeVerifier: verifier, state }, { Cookie: "" });
  assert.equal(exchanged.status, 200);
  const credentials = await exchanged.json() as any;
  assert.equal(await verifyServiceToken(credentials.serviceToken, f.env.SERVICE_TOKEN_SECRET), true);
  assert.equal((await f.call("token", { sharingGrant: credentials.sharingGrant })).status, 200);
  delete f.env.STRIPE_COMPLIMENTARY_COUPON_ID;
  assert.equal((await f.call("token", { sharingGrant: credentials.sharingGrant })).status, 401);
  assert.equal(intentReads, 0);
});
test("unapproved or incomplete zero-cost sessions cannot connect or receive recovery email", async () => {
  const cases: [string, (f: ReturnType<typeof complimentaryFixture>) => void][] = [
    ["disabled configuration", f => { delete f.env.STRIPE_COMPLIMENTARY_COUPON_ID; }],
    ["different coupon", f => { f.session.discounts[0].coupon = "UnapprovedCoupon"; }],
    ["stacked discounts", f => { f.session.discounts.push({ coupon: complimentaryCoupon }); }],
    ["nonzero total", f => { f.session.amount_total = 1; }],
    ["free price", f => { f.session.amount_subtotal = 0; f.session.total_details.amount_discount = 0; }],
    ["partial discount", f => { f.session.total_details.amount_discount = 2899; }],
    ["present PaymentIntent", f => { f.session.payment_intent = "pi_pending"; }],
    ["open session", f => { f.session.status = "open"; }],
    ["wrong product", f => { f.session.metadata.product = "another-app"; }],
    ["wrong mode", f => { f.session.mode = "setup"; }],
    ["wrong price", f => { f.session.line_items.data[0].price.id = "price_other"; }],
    ["wrong quantity", f => { f.session.line_items.data[0].quantity = 2; }],
    ["wrong Stripe environment", f => { f.session.livemode = true; }],
  ];
  for (const [name, mutate] of cases) {
    const f = complimentaryFixture();
    mutate(f);
    assert.equal((await f.call("authorize", { codeChallenge: challenge, state })).status, 401, name);
    const restored = await f.call("restore", { email: "buyer@example.com" });
    assert.equal(restored.status, 200, name);
    assert.deepEqual(await restored.json(), { sent: true }, name);
    assert.equal(f.sent.length, 0, name);
    assert.equal(f.objects.size, 0, name);
  }
});
test("recovery is neutral for unmatched email and sends only to the verified order address", async () => {
  const f = fixture();
  assert.deepEqual(await (await f.call("restore", { email: "missing@example.com" })).json(), { sent: true }); assert.equal(f.sent.length, 0);
  const r = await f.call("restore", { email: "buyer@example.com", codeChallenge: challenge, state });
  assert.deepEqual(await r.json(), { sent: true }); assert.equal(f.sent.length, 1); assert.equal(f.sent[0].to, "buyer@example.com");
  const link = new URL(f.sent[0].url); assert.equal(link.origin, "https://screencast.to"); assert.equal(link.searchParams.get("state"), state);
  const token = link.searchParams.get("restore")!;
  const restored = await f.call("restore/complete", { token }); assert.equal(restored.status, 200);
  assert.match(restored.headers.get("Set-Cookie")!, /HttpOnly; SameSite=Lax; Secure/);
  assert.equal((await f.call("restore/complete", { token })).status, 401);
  assert.equal((await f.call("exchange", { code: token, codeVerifier: verifier, state })).status, 401);
});
test("restore tokens expire, don't survive refunds, and never authorize uploads directly", async () => {
  for (const mode of ["expire", "refund"]) {
    const f = fixture(); await f.call("restore", { email: "buyer@example.com" });
    const token = new URL(f.sent[0].url).searchParams.get("restore")!;
    assert.equal((await f.call("token", { sharingGrant: token })).status, 401);
    if (mode === "expire") f.advance(901); else f.charge.refunded = true;
    assert.equal((await f.call("restore/complete", { token })).status, 401);
  }
});
test("CSRF, malformed binding, oversized body and rate limits fail closed", async () => {
  const f = fixture();
  assert.equal((await f.call("authorize", { codeChallenge: challenge, state }, { Origin: "https://evil.example" })).status, 403);
  assert.equal((await f.call("restore", { email: "buyer@example.com", state })).status, 400);
  assert.equal((await f.call("exchange", { code: "a".repeat(9000) })).status, 413);
  f.env.SIGN_LIMITER.limit = async () => ({ success: false });
  assert.equal((await f.call("status")).status, 429);
});
test("Stripe outages expose no provider data and do not grant access", async () => {
  const f = fixture(); f.stripe.paymentIntents.retrieve = async () => { throw new Error("secret purchase details"); };
  const r = await f.call("status"); assert.equal(r.status, 503); assert.equal((await r.text()).includes("secret purchase"), false);
});

test("recovery searches email case-insensitively and delivers only to the original verified address", async () => {
  const f = fixture();
  const verifiedAddress = "Buyer@Example.COM";
  f.session.customer_details.email = verifiedAddress;
  const searches: any[] = [];
  f.stripe.customers.list = () => assert.fail("Recovery must not use Stripe's case-sensitive email list filter");
  f.stripe.customers.search = async (parameters: any) => {
    searches.push(parameters);
    return { data: [{ id: "cus_buyer", email: verifiedAddress }], has_more: false };
  };
  const response = await f.call("restore", { email: "BUYER@EXAMPLE.COM", codeChallenge: challenge, state });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { sent: true });
  assert.deepEqual(searches, [{ query: 'email:"buyer@example.com"', limit: 5 }]);
  assert.equal(f.sent.length, 1);
  assert.equal(f.sent[0].to, verifiedAddress);
});

test("a missing service-token secret disables all sharing authorization before Stripe or email access", async () => {
  const f = fixture();
  delete (f.env as Partial<Env>).SERVICE_TOKEN_SECRET;
  let stripeCalls = 0;
  f.dependencies.stripeFactory = () => { stripeCalls += 1; return f.stripe; };
  for (const [route, body] of [
    ["status", undefined], ["authorize", { codeChallenge: challenge, state }],
    ["exchange", { code: "c".repeat(43), codeVerifier: verifier, state }],
    ["token", { sharingGrant: "opaque" }], ["restore", { email: "buyer@example.com" }],
    ["restore/complete", { token: "t".repeat(43) }],
  ] as [string, unknown][]) {
    assert.equal((await f.call(route, body)).status, 503, route);
  }
  assert.equal(stripeCalls, 0);
  assert.equal(f.sent.length, 0);
  assert.equal(f.objects.size, 0);
});

test("recovery stops after its customer-search pagination budget", async () => {
  const f = fixture();
  const searches: any[] = [];
  f.stripe.customers.search = async (parameters: any) => {
    searches.push(parameters);
    assert.ok(searches.length <= 2, "Search must not auto-paginate indefinitely");
    return { data: [{ id: "cus_other", email: "other@example.com" }], has_more: true, next_page: "next-customer-page" };
  };
  f.stripe.checkout.sessions.list = () => assert.fail("Nonmatching customer addresses must not be inspected");
  const response = await f.call("restore", { email: "buyer@example.com" });
  assert.deepEqual(await response.json(), { sent: true });
  assert.equal(searches.length, 2);
  assert.equal(searches[0].page, undefined);
  assert.equal(searches[1].page, "next-customer-page");
  assert.equal(f.sent.length, 0);
});

test("recovery bounds session-list pages and paid-session checks even when Stripe advertises more results", async () => {
  for (const eligibleAddress of [false, true]) {
    const f = fixture();
    f.charge.refunded = true;
    let listCalls = 0, purchaseChecks = 0;
    f.stripe.customers.search = async () => ({
      data: Array.from({ length: 5 }, (_, index) => ({ id: `cus_${index}`, email: "buyer@example.com" })),
      has_more: true, next_page: "more-customers",
    });
    f.stripe.checkout.sessions.list = async (parameters: any) => {
      listCalls += 1;
      assert.ok(listCalls <= 10, "Session lists must stop at the global page budget");
      assert.equal(parameters.limit, 10);
      return {
        data: Array.from({ length: 10 }, (_, index) => ({
          id: `cs_test_recovery${listCalls}${index}1234567890`,
          customer_details: { email: eligibleAddress ? "buyer@example.com" : "other@example.com" },
        })), has_more: true,
        async *[Symbol.asyncIterator]() { assert.fail("Recovery must not use unbounded SDK pagination"); },
      };
    };
    f.stripe.checkout.sessions.retrieve = async () => {
      purchaseChecks += 1;
      assert.ok(purchaseChecks <= 10, "Paid-session validation must stop at its global budget");
      return f.session;
    };
    const response = await f.call("restore", { email: "buyer@example.com" });
    assert.deepEqual(await response.json(), { sent: true });
    assert.equal(f.sent.length, 0);
    if (eligibleAddress) assert.equal(purchaseChecks, 10);
    else assert.equal(listCalls, 10);
  }
});
