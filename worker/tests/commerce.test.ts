import assert from "node:assert/strict";
import test from "node:test";
import { commerceInternals, handleCommerce } from "../src/commerce";
import type { Env } from "../src/env";

const publishToken = "release-publish-token-that-is-at-least-thirty-two-characters";
const updateToken = "sparkle-update-token-that-is-at-least-thirty-two-characters";
const sha256 = "a".repeat(64);

function fakeEnv() {
  const objects = new Map<string, { bytes: Uint8Array; customMetadata?: Record<string, string> }>();
  const bucket = {
    async head(key: string) {
      const value = objects.get(key);
      return value ? { key, size: value.bytes.byteLength, customMetadata: value.customMetadata } : null;
    },
    async get(key: string) {
      const value = objects.get(key);
      if (!value) return null;
      return {
        key, size: value.bytes.byteLength, httpEtag: '"etag"', customMetadata: value.customMetadata,
        body: new Response(value.bytes).body,
        async json() { return JSON.parse(new TextDecoder().decode(value.bytes)); },
      };
    },
    async put(key: string, body: ReadableStream | ArrayBuffer, options?: R2PutOptions) {
      const bytes = body instanceof ArrayBuffer
        ? new Uint8Array(body)
        : new Uint8Array(await new Response(body).arrayBuffer());
      objects.set(key, { bytes, customMetadata: options?.customMetadata });
      return { key, size: bytes.byteLength };
    },
  };
  const env = {
    RELEASES: bucket,
    RELEASE_PUBLISH_TOKEN: publishToken,
    SPARKLE_UPDATE_TOKEN: updateToken,
    STRIPE_SECRET_KEY: "sk_test_1234567890",
    STRIPE_PRICE_ID: "price_current",
    STRIPE_ALLOWED_PRICE_IDS: "price_old",
    CHECKOUT_BASE_URL: "https://screencast.to",
    CHECKOUT_ENABLED: "false",
  } as unknown as Env;
  return { env, objects };
}

function upload(path: string, body: BodyInit, contentType: string, extra: Record<string, string> = {}) {
  const length = body instanceof Uint8Array ? body.byteLength : Buffer.byteLength(String(body));
  return new Request(`https://screencast.to/api/publish?path=${encodeURIComponent(path)}`, {
    method: "PUT",
    headers: {
      Authorization: `Bearer ${publishToken}`,
      "Content-Length": String(length),
      "Content-Type": contentType,
      ...extra,
    },
    body,
  });
}

test("commerce validates release manifests, allowlisted prices, and bearer tokens", () => {
  const manifest = {
    product: "screencast-mac", version: "3.0.0", pathname: "releases/screencast-3.0.0.dmg",
    appcastPath: "releases/appcast-3.0.0.xml", size: 3, sha256,
  };
  assert.equal(commerceInternals.validManifest(manifest), true);
  assert.equal(commerceInternals.validManifest({ ...manifest, pathname: "releases/other.dmg" }), false);
  assert.deepEqual([...commerceInternals.priceIds(fakeEnv().env)], ["price_current", "price_old"]);
  assert.equal(commerceInternals.tokenMatches(new Request("https://example.com", {
    headers: { Authorization: `Bearer ${updateToken}` },
  }), updateToken), true);
});

test("release publication keeps versioned objects immutable and publishes the manifest last", async () => {
  const { env, objects } = fakeEnv();
  const dmg = new Uint8Array([1, 2, 3]);
  let response = await handleCommerce(upload("releases/screencast-3.0.0.dmg", dmg,
    "application/x-apple-diskimage", { "X-Release-SHA256": sha256 }), env);
  assert.equal(response?.status, 200);
  assert.equal((await handleCommerce(upload("releases/screencast-3.0.0.dmg", dmg,
    "application/x-apple-diskimage", { "X-Release-SHA256": sha256 }), env))?.status, 409);

  const appcast = "<rss/>";
  response = await handleCommerce(upload("releases/appcast-3.0.0.xml", appcast, "application/xml"), env);
  assert.equal(response?.status, 200);

  const manifest = JSON.stringify({
    product: "screencast-mac", version: "3.0.0", pathname: "releases/screencast-3.0.0.dmg",
    appcastPath: "releases/appcast-3.0.0.xml", size: 3, sha256,
  });
  response = await handleCommerce(upload("releases/current.json", manifest, "application/json"), env);
  assert.equal(response?.status, 200);
  assert.equal(objects.has("releases/current.json"), true);
});

test("release publication rejects bad authorization, unrelated paths, and incomplete manifests", async () => {
  const { env } = fakeEnv();
  const unauthorized = upload("releases/appcast-3.0.0.xml", "<rss/>", "application/xml");
  unauthorized.headers.set("Authorization", "Bearer wrong");
  assert.equal((await handleCommerce(unauthorized, env))?.status, 401);
  assert.equal((await handleCommerce(upload("private/data.json", "{}", "application/json"), env))?.status, 400);
  const manifest = JSON.stringify({
    product: "screencast-mac", version: "3.0.0", pathname: "releases/screencast-3.0.0.dmg",
    appcastPath: "releases/appcast-3.0.0.xml", size: 3, sha256,
  });
  assert.equal((await handleCommerce(upload("releases/current.json", manifest, "application/json"), env))?.status, 409);
});

test("checkout carries the Screencast brand and returns to the private delivery flow", async () => {
  const { env, objects } = fakeEnv();
  env.CHECKOUT_ENABLED = "true";
  const manifest = {
    product: "screencast-mac", version: "3.0.0", pathname: "releases/screencast-3.0.0.dmg",
    appcastPath: "releases/appcast-3.0.0.xml", size: 3, sha256,
  };
  objects.set("releases/current.json", {
    bytes: new TextEncoder().encode(JSON.stringify(manifest)),
  });

  let checkoutParams: Record<string, unknown> | undefined;
  const stripe = {
    prices: {
      async retrieve() {
        return {
          id: "price_current", active: true, type: "one_time", billing_scheme: "per_unit",
          recurring: null, custom_unit_amount: null, transform_quantity: null, livemode: false,
          unit_amount: 2900, currency: "usd", product: { active: true, deleted: false },
        };
      },
    },
    checkout: {
      sessions: {
        async create(params: Record<string, unknown>) {
          checkoutParams = params;
          return { url: "https://checkout.stripe.com/c/pay/cs_test_screencast" };
        },
      },
    },
  };
  const response = await handleCommerce(new Request("https://screencast.to/api/checkout", {
    method: "POST", headers: { Origin: "https://screencast.to", "Sec-Fetch-Site": "same-origin" },
  }), env, { stripeFactory: () => stripe as unknown as import("stripe").default });

  assert.equal(response?.status, 303);
  assert.equal(response?.headers.get("Location"), "https://checkout.stripe.com/c/pay/cs_test_screencast");
  assert.equal(checkoutParams?.mode, "payment");
  assert.deepEqual(checkoutParams?.managed_payments, { enabled: false });
  assert.equal(checkoutParams?.customer_creation, "always");
  assert.equal(checkoutParams?.submit_type, "pay");
  assert.deepEqual(checkoutParams?.line_items, [{ price: "price_current", quantity: 1 }]);
  assert.deepEqual(checkoutParams?.metadata, { product: "screencast-mac" });
  assert.deepEqual(checkoutParams?.branding_settings, {
    background_color: "#f5f0e6",
    border_style: "rectangular",
    button_color: "#f0444d",
    display_name: "Screencast.to",
    font_family: "inter",
    icon: { type: "url", url: "https://screencast.to/assets/icon.png" },
  });
  assert.deepEqual(checkoutParams?.custom_text, {
    submit: { message: "One payment. No subscription. Includes signed updates for this edition." },
    after_submit: { message: "After payment, you'll return to Screencast.to for your private Mac download." },
  });
  assert.deepEqual(checkoutParams?.payment_intent_data, { description: "Screencast.to for Mac" });
  assert.equal(checkoutParams?.success_url,
    "https://screencast.to/api/complete?session_id={CHECKOUT_SESSION_ID}");
  assert.equal(checkoutParams?.cancel_url, "https://screencast.to/?checkout=cancelled");
});

test("Sparkle serves only the current named update through its clean release URL", async () => {
  const { env, objects } = fakeEnv();
  const dmg = new Uint8Array([1, 2, 3]);
  const manifest = {
    product: "screencast-mac", version: "3.0.0", pathname: "releases/screencast-3.0.0.dmg",
    appcastPath: "releases/appcast-3.0.0.xml", size: dmg.byteLength, sha256,
  };
  objects.set("releases/current.json", {
    bytes: new TextEncoder().encode(JSON.stringify(manifest)),
  });
  objects.set(manifest.pathname, { bytes: dmg, customMetadata: { sha256 } });

  const authorized = { Authorization: `Bearer ${updateToken}` };
  let response = await handleCommerce(new Request(
    "https://screencast.to/api/update/screencast-3.0.0.dmg", { headers: authorized }), env);
  assert.equal(response?.status, 200);
  assert.equal(response?.headers.get("Content-Type"), "application/x-apple-diskimage");

  response = await handleCommerce(new Request(
    "https://screencast.to/api/update/screencast-2.0.0.dmg", { headers: authorized }), env);
  assert.equal(response?.status, 404);
  assert.equal((await handleCommerce(new Request(
    "https://screencast.to/api/update/screencast-3.0.0.dmg"), env))?.status, 401);
});
