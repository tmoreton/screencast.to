import Stripe from "stripe";
import type { Env } from "./env";

const PRODUCT = "screencast-mac";
const DEFAULT_MANIFEST = "releases/current.json";
const VERSION = /^[1-9][0-9]{0,3}\.(?:0|[1-9][0-9]?)\.(?:0|[1-9][0-9]?)$/;
const SHA256 = /^[a-f0-9]{64}$/;
const SESSION = /^cs_(?:test|live)_[A-Za-z0-9]{10,}$/;
const COOKIE = "__Host-screencast-purchase";
const COOKIE_AGE = 30 * 24 * 60 * 60;

interface ReleaseManifest {
  product: "screencast-mac";
  version: string;
  pathname: string;
  appcastPath: string;
  size: number;
  sha256: string;
  publishedAt?: string;
}

interface CommerceDependencies {
  stripeFactory?: (env: Env) => Stripe;
  logger?: Pick<Console, "error">;
}

function privateResponse(body: BodyInit | null, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  headers.set("Cache-Control", "private, no-store, max-age=0");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("X-Content-Type-Options", "nosniff");
  return new Response(body, { ...init, headers });
}

function json(body: unknown, status = 200): Response {
  return privateResponse(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function stripeMode(env: Env): "test" | "live" | null {
  return /^(?:sk|rk)_(test|live)_[A-Za-z0-9]+$/.exec(env.STRIPE_SECRET_KEY || "")?.[1] as
    "test" | "live" | undefined ?? null;
}

function stripeClient(env: Env): Stripe {
  if (!stripeMode(env)) throw new Error("Stripe is not configured");
  return new Stripe(env.STRIPE_SECRET_KEY, { maxNetworkRetries: 2 });
}

function baseUrl(env: Env): URL | null {
  try {
    const value = new URL(env.CHECKOUT_BASE_URL);
    if (value.protocol === "https:" && value.pathname === "/" && !value.search && !value.hash &&
        !value.username && !value.password) return value;
  } catch { /* Invalid configuration keeps checkout disabled. */ }
  return null;
}

function manifestPath(env: Env): string | null {
  const value = env.RELEASE_MANIFEST_PATH || DEFAULT_MANIFEST;
  return /^releases\/[A-Za-z0-9._-]+\.json$/.test(value) ? value : null;
}

function priceIds(env: Env): Set<string> {
  return new Set([env.STRIPE_PRICE_ID || "", env.STRIPE_ALLOWED_PRICE_IDS || ""]
    .join(",").split(",").map((value) => value.trim())
    .filter((value) => /^price_[A-Za-z0-9]+$/.test(value)));
}

function validManifest(value: unknown): value is ReleaseManifest {
  if (!value || typeof value !== "object") return false;
  const release = value as Record<string, unknown>;
  return release.product === PRODUCT && VERSION.test(String(release.version || "")) &&
    release.pathname === `releases/screencast-${release.version}.dmg` &&
    release.appcastPath === `releases/appcast-${release.version}.xml` &&
    SHA256.test(String(release.sha256 || "")) && Number.isSafeInteger(release.size) &&
    Number(release.size) > 0;
}

async function currentRelease(env: Env): Promise<ReleaseManifest | null> {
  const path = manifestPath(env);
  if (!path) return null;
  const object = await env.RELEASES.get(path);
  if (!object) return null;
  try {
    const value: unknown = await object.json();
    return validManifest(value) ? value : null;
  } catch { return null; }
}

function requestedSession(request: Request, mode: "test" | "live"): string | null {
  const url = new URL(request.url);
  if (url.searchParams.has("session_id")) {
    const values = url.searchParams.getAll("session_id");
    const value = values.length === 1 ? values[0] : null;
    return value && SESSION.test(value) && value.startsWith(`cs_${mode}_`) ? value : null;
  }
  const matches = (request.headers.get("Cookie") || "").split(";")
    .map((part) => part.trim()).filter((part) => part.startsWith(`${COOKIE}=`));
  if (matches.length !== 1) return null;
  try {
    const value = decodeURIComponent(matches[0].slice(COOKIE.length + 1));
    return SESSION.test(value) && value.startsWith(`cs_${mode}_`) ? value : null;
  } catch { return null; }
}

function isProductSession(session: Stripe.Checkout.Session | null, allowed: Set<string>): boolean {
  if (!session || session.mode !== "payment" || session.metadata?.product !== PRODUCT ||
      allowed.size === 0) return false;
  const items = session.line_items?.data;
  return Array.isArray(items) && !session.line_items?.has_more && items.length === 1 &&
    items[0].quantity === 1 && allowed.has(typeof items[0].price === "string" ? items[0].price :
      items[0].price?.id || "");
}

async function loadSession(stripe: Stripe, id: string | null, allowed: Set<string>,
  mode: "test" | "live"): Promise<Stripe.Checkout.Session | null> {
  if (!id || !SESSION.test(id) || !id.startsWith(`cs_${mode}_`)) return null;
  try {
    const session = await stripe.checkout.sessions.retrieve(id, { expand: ["line_items"] });
    if (session.livemode !== (mode === "live") || !isProductSession(session, allowed)) return null;
    return session;
  } catch (error) {
    if ((error as { code?: string }).code === "resource_missing") return null;
    throw error;
  }
}

function tokenMatches(request: Request, expected: string | undefined): boolean {
  if (!expected || expected.length < 32) return false;
  const authorization = request.headers.get("Authorization") || "";
  const supplied = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (supplied.length !== expected.length) return false;
  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= supplied.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return difference === 0;
}

function objectResponse(object: R2ObjectBody, contentType: string, filename?: string): Response {
  const headers = new Headers({
    "Content-Type": contentType,
    "Content-Length": String(object.size),
    ETag: object.httpEtag,
  });
  if (filename) headers.set("Content-Disposition", `attachment; filename="${filename}"`);
  return privateResponse(object.body, { status: 200, headers });
}

async function loadPrice(stripe: Stripe, env: Env, mode: "test" | "live") {
  if (!/^price_[A-Za-z0-9]+$/.test(env.STRIPE_PRICE_ID || "")) return null;
  const price = await stripe.prices.retrieve(env.STRIPE_PRICE_ID, { expand: ["product"] });
  const product = typeof price.product === "string" || price.product.deleted ? null : price.product;
  if (price.id !== env.STRIPE_PRICE_ID || !price.active || price.type !== "one_time" ||
      price.billing_scheme !== "per_unit" || price.recurring || price.custom_unit_amount ||
      price.transform_quantity || price.livemode !== (mode === "live") ||
      !Number.isSafeInteger(price.unit_amount) || Number(price.unit_amount) <= 0 ||
      !/^[a-z]{3}$/.test(price.currency || "") || !product?.active) return null;
  const formatter = new Intl.NumberFormat("en-US", { style: "currency", currency: price.currency });
  const decimals = ["isk", "ugx"].includes(price.currency)
    ? 2 : (formatter.resolvedOptions().maximumFractionDigits ?? 2);
  return {
    amount: price.unit_amount,
    currency: price.currency,
    formatted: formatter.format(Number(price.unit_amount) / (10 ** decimals)),
  };
}

const uploadPolicies = [
  { pattern: new RegExp(`^releases/screencast-${VERSION.source.slice(1, -1)}\\.dmg$`),
    contentType: "application/x-apple-diskimage", max: 100 * 1024 * 1024, overwrite: false },
  { pattern: new RegExp(`^releases/appcast-${VERSION.source.slice(1, -1)}\\.xml$`),
    contentType: "application/xml", max: 2 * 1024 * 1024, overwrite: false },
  { pattern: /^releases\/current\.json$/,
    contentType: "application/json", max: 16 * 1024, overwrite: true },
];

async function publishRelease(request: Request, env: Env): Promise<Response> {
  if (!tokenMatches(request, env.RELEASE_PUBLISH_TOKEN)) {
    return json({ error: "Release authorization required." }, 401);
  }
  const url = new URL(request.url);
  const pathname = url.searchParams.get("path") || "";
  const policy = uploadPolicies.find(({ pattern }) => pattern.test(pathname));
  const length = Number(request.headers.get("Content-Length"));
  if (!policy || request.headers.get("Content-Type")?.split(";", 1)[0] !== policy.contentType ||
      !Number.isSafeInteger(length) || length <= 0 || length > policy.max || !request.body) {
    return json({ error: "Release upload is not allowed." }, 400);
  }
  if (!policy.overwrite && await env.RELEASES.head(pathname)) {
    return json({ error: "The immutable release object already exists." }, 409);
  }

  let body: ReadableStream | ArrayBuffer = request.body;
  let manifest: ReleaseManifest | null = null;
  if (pathname.endsWith(".json") || pathname.endsWith(".xml")) {
    const buffer = await request.arrayBuffer();
    if (buffer.byteLength !== length) return json({ error: "Release upload length mismatch." }, 400);
    body = buffer;
    if (pathname.endsWith(".json")) {
      try {
        const value: unknown = JSON.parse(new TextDecoder().decode(buffer));
        if (!validManifest(value)) throw new Error("invalid manifest");
        manifest = value;
      } catch { return json({ error: "Release manifest is invalid." }, 400); }
      const [dmg, appcast] = await Promise.all([
        env.RELEASES.head(manifest.pathname), env.RELEASES.head(manifest.appcastPath),
      ]);
      if (!dmg || !appcast || dmg.size !== manifest.size ||
          dmg.customMetadata?.sha256 !== manifest.sha256) {
        return json({ error: "Release artifacts are incomplete or do not match the manifest." }, 409);
      }
    }
  }

  const sha256 = request.headers.get("X-Release-SHA256") || "";
  if (pathname.endsWith(".dmg") && !SHA256.test(sha256)) {
    return json({ error: "Release checksum is required." }, 400);
  }
  const result = await env.RELEASES.put(pathname, body, {
    httpMetadata: { contentType: policy.contentType, cacheControl: "private, no-store" },
    customMetadata: pathname.endsWith(".dmg") ? { sha256 } : undefined,
  });
  if (!result || result.size !== length) return json({ error: "Release upload failed." }, 502);
  return json({ ok: true, pathname, size: result.size });
}

export async function handleCommerce(request: Request, env: Env,
  dependencies: CommerceDependencies = {}): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/api/")) return null;
  const mode = stripeMode(env);
  const stripeFactory = dependencies.stripeFactory || stripeClient;
  const logger = dependencies.logger || console;
  const report = (message: string, error: unknown) =>
    logger.error(message, (error as { type?: string; name?: string })?.type ||
      (error as { name?: string })?.name || "unknown");

  if (url.pathname === "/api/publish" && request.method === "PUT") {
    try { return await publishRelease(request, env); }
    catch (error) { report("Release upload failed:", error); return json({ error: "Release upload failed." }, 502); }
  }
  if (url.pathname === "/api/config" && request.method === "GET") {
    const body = { enabled: false, mode, price: null as Awaited<ReturnType<typeof loadPrice>>, downloadReady: false };
    if (!mode || !baseUrl(env) || !/^price_[A-Za-z0-9]+$/.test(env.STRIPE_PRICE_ID || "")) return json(body);
    try {
      const [price, release] = await Promise.all([loadPrice(stripeFactory(env), env, mode), currentRelease(env)]);
      body.price = price;
      body.downloadReady = Boolean(release);
      body.enabled = env.CHECKOUT_ENABLED === "true" && Boolean(price && release);
      return json(body);
    } catch (error) { report("Checkout configuration check failed:", error); return json(body, 503); }
  }
  if (url.pathname === "/api/checkout" && request.method === "POST") {
    const site = baseUrl(env);
    if (!mode || !site || env.CHECKOUT_ENABLED !== "true") return privateResponse("Checkout is not ready.", { status: 503 });
    const origin = request.headers.get("Origin");
    const fetchSite = request.headers.get("Sec-Fetch-Site");
    if ((origin && origin !== site.origin) || (fetchSite && !["same-origin", "none"].includes(fetchSite))) {
      return privateResponse("Cross-site checkout is not allowed.", { status: 403 });
    }
    try {
      const stripe = stripeFactory(env);
      const [price, release] = await Promise.all([loadPrice(stripe, env, mode), currentRelease(env)]);
      if (!price || !release) return privateResponse("Checkout is not ready.", { status: 503 });
      const session = await stripe.checkout.sessions.create({
        mode: "payment", line_items: [{ price: env.STRIPE_PRICE_ID, quantity: 1 }],
        customer_creation: "always",
        submit_type: "pay",
        branding_settings: {
          background_color: "#f5f0e6",
          border_style: "rectangular",
          button_color: "#f0444d",
          display_name: "Screencast.to",
          font_family: "inter",
          icon: { type: "url", url: new URL("/assets/icon.png", site).href },
        },
        custom_text: {
          submit: { message: "One payment. No subscription. Includes signed updates for this edition." },
          after_submit: { message: "After payment, you'll return to Screencast.to for your private Mac download." },
        },
        payment_intent_data: { description: "Screencast.to for Mac" },
        success_url: new URL("/api/complete?session_id={CHECKOUT_SESSION_ID}", site).href,
        cancel_url: new URL("/?checkout=cancelled", site).href,
        metadata: { product: PRODUCT },
      });
      const target = new URL(session.url || "");
      if (target.protocol !== "https:" || target.hostname !== "checkout.stripe.com" ||
          target.username || target.password || (target.port && target.port !== "443")) throw new Error("invalid redirect");
      return privateResponse(null, { status: 303, headers: { Location: target.href } });
    } catch (error) { report("Checkout session creation failed:", error); return privateResponse("Checkout is temporarily unavailable.", { status: 502 }); }
  }
  if (url.pathname === "/api/complete" && request.method === "GET") {
    if (!mode || !url.searchParams.has("session_id")) return privateResponse("Purchase link could not be verified.", { status: 403 });
    const session = requestedSession(request, mode);
    if (!session) return privateResponse("Purchase link could not be verified.", { status: 403 });
    const cookie = `${COOKIE}=${encodeURIComponent(session)}; Path=/; Max-Age=${COOKIE_AGE}; HttpOnly; SameSite=Lax; Secure`;
    return privateResponse(null, { status: 303, headers: { Location: "/confirmation.html", "Set-Cookie": cookie } });
  }
  if (url.pathname === "/api/status" && request.method === "GET") {
    const denied = { paid: false, pending: false, mode };
    if (!mode || priceIds(env).size === 0) return json(denied, 503);
    try {
      const allowed = priceIds(env);
      const session = await loadSession(stripeFactory(env), requestedSession(request, mode), allowed, mode);
      if (session?.status === "complete" && session.payment_status === "paid") return json({ paid: true, pending: false, mode });
      if (session && (session.status === "open" || (session.status === "complete" && session.payment_status === "unpaid"))) {
        return json({ paid: false, pending: true, mode }, 202);
      }
      return json(denied, 403);
    } catch (error) { report("Purchase status check failed:", error); return json(denied, 502); }
  }
  if (url.pathname === "/api/download" && request.method === "GET") {
    if (!mode || priceIds(env).size === 0) return privateResponse("The download is not ready.", { status: 503 });
    try {
      const [session, release] = await Promise.all([
        loadSession(stripeFactory(env), requestedSession(request, mode), priceIds(env), mode), currentRelease(env),
      ]);
      if (!session || session.status !== "complete" || session.payment_status !== "paid") return privateResponse("Purchase could not be verified.", { status: 403 });
      if (!release) return privateResponse("The download is not ready.", { status: 503 });
      const object = await env.RELEASES.get(release.pathname);
      return object ? objectResponse(object, "application/x-apple-diskimage", release.pathname.slice("releases/".length)) :
        privateResponse("The download is not ready.", { status: 503 });
    } catch (error) { report("Private download failed:", error); return privateResponse("The download is temporarily unavailable.", { status: 502 }); }
  }
  if (url.pathname === "/api/appcast" && request.method === "GET") {
    if (!tokenMatches(request, env.SPARKLE_UPDATE_TOKEN)) return privateResponse("Update authorization required.", { status: 401 });
    const release = await currentRelease(env);
    const object = release ? await env.RELEASES.get(release.appcastPath) : null;
    return object ? objectResponse(object, "application/xml; charset=utf-8") : privateResponse("No update feed is available.", { status: 404 });
  }
  if ((url.pathname === "/api/update" || url.pathname.startsWith("/api/update/")) && request.method === "GET") {
    if (!tokenMatches(request, env.SPARKLE_UPDATE_TOKEN)) return privateResponse("Update authorization required.", { status: 401 });
    const release = await currentRelease(env);
    const requestedFile = url.pathname.startsWith("/api/update/")
      ? url.pathname.slice("/api/update/".length)
      : url.searchParams.get("file");
    if (!release || requestedFile !== release.pathname.slice("releases/".length)) return privateResponse("Update not found.", { status: 404 });
    const object = await env.RELEASES.get(release.pathname);
    return object ? objectResponse(object, "application/x-apple-diskimage", release.pathname.slice("releases/".length)) :
      privateResponse("Update not found.", { status: 404 });
  }
  return privateResponse("Not found", { status: 404 });
}

export const commerceInternals = { validManifest, tokenMatches, priceIds };
