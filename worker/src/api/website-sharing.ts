import type Stripe from "stripe";
import type { Env } from "../env";
import { websitePurchase as purchase } from "../commerce";
import { issueServiceToken } from "../auth/service-token";
import { isPurchaseEmailConfigured, sendPurchaseRestoreEmail } from "../email";
import { readJSONBody } from "./request-body";

const PREFIX = "sharing-auth/";
const SHORT_TTL = 15 * 60;
const GRANT_TTL = 365 * 24 * 60 * 60;
const URL_SAFE = /^[A-Za-z0-9_-]{43}$/;
const STATE = /^[A-Za-z0-9_-]{32,128}$/;
const VERIFIER = /^[A-Za-z0-9._~-]{43,128}$/;
interface Ticket {
  v: 1; purpose: "connect" | "restore"; session: string; mode: "test" | "live";
  exp: number; challenge?: string; state?: string;
}
interface Grant { v: 1; purpose: "website-sharing"; session: string; mode: "test" | "live"; iat: number; exp: number }
interface Dependencies {
  stripeFactory?: (env: Env) => Stripe;
  now?: () => number;
  sendEmail?: typeof sendPurchaseRestoreEmail;
  logger?: Pick<Console, "error">;
}
function json(body: unknown, status = 200, extra: HeadersInit = {}): Response {
  const headers = new Headers(extra);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "private, no-store, max-age=0");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("X-Content-Type-Options", "nosniff");
  return new Response(JSON.stringify(body), { status, headers });
}
function denied(): Response { return json({ error: "Connect a verified website purchase to continue." }, 401); }
function encode(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function decode(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("Invalid token");
  return Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
}
async function digest(value: string): Promise<string> {
  return encode(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))));
}
async function key(secret: string): Promise<CryptoKey> {
  if (!secret || secret.length < 32) throw new Error("Sharing is not configured");
  const material = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), "HKDF", false, ["deriveKey"]);
  return crypto.subtle.deriveKey({ name: "HKDF", hash: "SHA-256", salt: new TextEncoder().encode("screencast.to"),
    info: new TextEncoder().encode("website-sharing-grant-v1") }, material,
  { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}
async function seal(value: Grant, secret: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await key(secret),
    new TextEncoder().encode(JSON.stringify(value))));
  const bytes = new Uint8Array(iv.length + encrypted.length); bytes.set(iv); bytes.set(encrypted, iv.length);
  return encode(bytes);
}
async function open(value: string, secret: string, mode: string, now: number): Promise<Grant | null> {
  try {
    if (value.length > 2048) return null;
    const bytes = decode(value);
    const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: bytes.slice(0, 12) }, await key(secret), bytes.slice(12));
    const grant = JSON.parse(new TextDecoder().decode(plain)) as Grant;
    return grant.v === 1 && grant.purpose === "website-sharing" && grant.mode === mode &&
      typeof grant.session === "string" && Number.isInteger(grant.iat) && Number.isInteger(grant.exp) &&
      grant.iat <= now + 60 && grant.exp > now && grant.exp - grant.iat === GRANT_TTL ? grant : null;
  } catch { return null; }
}

// Checkout's paid flag alone remains true after refunds. Inspect its actual charge too.
async function paidSession(stripe: Stripe, env: Env, id: string | null, mode: "test" | "live") {
  const session = await purchase.loadSession(stripe, id, purchase.priceIds(env), mode);
  if (session?.status !== "complete" || session.payment_status !== "paid") return null;
  const intentId = typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id;
  if (!intentId) return null;
  const intent = await stripe.paymentIntents.retrieve(intentId, { expand: ["latest_charge"] });
  const charge = typeof intent.latest_charge === "object" ? intent.latest_charge : null;
  if (intent.livemode !== (mode === "live") || intent.status !== "succeeded" || !charge ||
      charge.livemode !== (mode === "live") || !charge.paid || !charge.captured || charge.status !== "succeeded" ||
      charge.refunded || charge.amount_refunded !== 0 || charge.disputed) return null;
  return session;
}
async function ticketKey(token: string): Promise<string> { return PREFIX + await digest(token); }
async function makeTicket(env: Env, ticket: Ticket): Promise<string> {
  const token = encode(crypto.getRandomValues(new Uint8Array(32)));
  await env.RELEASES.put(await ticketKey(token), JSON.stringify(ticket), {
    customMetadata: { expires: String(ticket.exp) }, httpMetadata: { cacheControl: "private, no-store" },
  });
  // Only this feature's expired records are removed. Keep abandoned browser links bounded.
  const expired = await env.RELEASES.list({ prefix: PREFIX, limit: 100, include: ["customMetadata"] });
  const now = ticket.exp - SHORT_TTL;
  const keys = expired.objects.filter(o => Number(o.customMetadata?.expires) < now).map(o => o.key);
  if (keys.length) await env.RELEASES.delete(keys);
  return token;
}
async function readTicket(env: Env, token: unknown, purpose: Ticket["purpose"], mode: string, now: number) {
  if (typeof token !== "string" || !URL_SAFE.test(token)) return null;
  const path = await ticketKey(token);
  const object = await env.RELEASES.get(path);
  if (!object) return null;
  const ticket = await object.json<Ticket>();
  return ticket.v === 1 && ticket.purpose === purpose && ticket.mode === mode && ticket.exp > now &&
    ticket.exp <= now + SHORT_TTL && typeof ticket.session === "string" ? { path, object, ticket } : null;
}
async function consume(env: Env, record: NonNullable<Awaited<ReturnType<typeof readTicket>>>): Promise<boolean> {
  // R2's conditional write makes concurrent redemption atomic. Never accept the same code twice.
  const claimed = await env.RELEASES.put(record.path, "{}", {
    onlyIf: { etagMatches: record.object.etag }, customMetadata: { expires: String(record.ticket.exp) },
  });
  if (!claimed) return false;
  await env.RELEASES.delete(record.path);
  return true;
}
async function credentials(env: Env, session: string, mode: "test" | "live", now: number) {
  const grant: Grant = { v: 1, purpose: "website-sharing", session, mode, iat: now, exp: now + GRANT_TTL };
  const [sharingGrant, service] = await Promise.all([seal(grant, env.SERVICE_TOKEN_SECRET), issueServiceToken(env.SERVICE_TOKEN_SECRET, now)]);
  return json({ sharingGrant, serviceToken: service.token, expiresAt: service.expiresAt });
}
function validBinding(body: Record<string, unknown>, optional = false): boolean {
  if (optional && body.codeChallenge === undefined && body.state === undefined) return true;
  return typeof body.codeChallenge === "string" && URL_SAFE.test(body.codeChallenge) &&
    typeof body.state === "string" && STATE.test(body.state);
}
async function findPurchase(stripe: Stripe, env: Env, email: string, mode: "test" | "live") {
  // Stripe Search matches email case-insensitively; Customers.list's email
  // filter is case-sensitive. Escape the quoted query and still compare the
  // complete stored address before inspecting any purchase.
  const normalizedEmail = email.toLowerCase();
  const escapedEmail = email.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  let customerPage: string | undefined;
  let remainingSessionPages = 10;
  let remainingSessionChecks = 10;
  // Explicit pages avoid SDK async iterators silently scanning unbounded
  // purchase history. At most 32 Stripe requests are made by this lookup.
  for (let pageIndex = 0; pageIndex < 2; pageIndex += 1) {
    const customers = await stripe.customers.search({
      query: `email:"${escapedEmail}"`, limit: 5, ...(customerPage ? { page: customerPage } : {}),
    });
    for (const customer of customers.data) {
      if (customer.email?.toLowerCase() !== normalizedEmail) continue;
      let startingAfter: string | undefined;
      for (let sessionPage = 0; sessionPage < 2 && remainingSessionPages > 0; sessionPage += 1) {
        remainingSessionPages -= 1;
        const sessions = await stripe.checkout.sessions.list({
          customer: customer.id, status: "complete", limit: 10,
          ...(startingAfter ? { starting_after: startingAfter } : {}),
        });
        for (const session of sessions.data) {
          const recipient = session.customer_details?.email || session.customer_email || customer.email;
          if (recipient?.toLowerCase() !== normalizedEmail) continue;
          if (remainingSessionChecks-- <= 0) return null;
          const paid = await paidSession(stripe, env, session.id, mode);
          if (paid) return { session: paid.id, recipient };
        }
        if (!sessions.has_more || sessions.data.length === 0) break;
        startingAfter = sessions.data[sessions.data.length - 1].id;
      }
      if (remainingSessionPages === 0 || remainingSessionChecks === 0) return null;
    }
    if (!customers.has_more || !customers.next_page) break;
    customerPage = customers.next_page;
  }
  return null;
}
export async function handleWebsiteSharing(request: Request, env: Env, dependencies: Dependencies = {}): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/api/sharing/")) return null;
  const mode = purchase.stripeMode(env), site = purchase.baseUrl(env);
  if (!mode || !site || !env.SERVICE_TOKEN_SECRET || env.SERVICE_TOKEN_SECRET.length < 32 || purchase.priceIds(env).size === 0 || env.UPLOAD_AUTH_MODE !== "app-store") {
    return json({ error: "Purchase connection is temporarily unavailable." }, 503);
  }
  const route = url.pathname.slice("/api/sharing/".length);
  const browser = ["authorize", "restore", "restore/complete"].includes(route);
  const origin = request.headers.get("Origin"), fetchSite = request.headers.get("Sec-Fetch-Site");
  if ((origin && origin !== site.origin) || (browser && origin !== site.origin) ||
      (fetchSite && !["same-origin", "none"].includes(fetchSite))) return json({ error: "Cross-site request denied." }, 403);
  if ((route === "status" ? request.method !== "GET" : request.method !== "POST") ||
      !["status", "authorize", "exchange", "token", "restore", "restore/complete"].includes(route)) return json({ error: "Not found." }, 404);
  if (url.search) return json({ error: "Invalid request." }, 400);
  const now = dependencies.now?.() ?? Math.floor(Date.now() / 1000);
  try {
    const limit = await env.SIGN_LIMITER.limit({ key: `website-sharing:${route}:${request.headers.get("CF-Connecting-IP") || "unknown"}` });
    if (!limit.success) return json({ error: "Please wait a minute and try again." }, 429);
    const stripe = (dependencies.stripeFactory || purchase.stripeClient)(env);
    if (route === "status") {
      const paid = await paidSession(stripe, env, purchase.requestedSession(request, mode), mode);
      return json({ paid: Boolean(paid), mode, recoveryAvailable: isPurchaseEmailConfigured(env) });
    }
    const parsed = await readJSONBody(request, 8192);
    if (!parsed.ok) return json({ error: "Invalid request." }, parsed.status);
    const body = parsed.value as Record<string, unknown>;
    if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "Invalid request." }, 400);
    if (route === "authorize") {
      if (!validBinding(body)) return json({ error: "Invalid app connection." }, 400);
      const session = await paidSession(stripe, env, purchase.requestedSession(request, mode), mode);
      if (!session) return denied();
      const code = await makeTicket(env, { v: 1, purpose: "connect", session: session.id, mode, exp: now + SHORT_TTL,
        challenge: body.codeChallenge as string, state: body.state as string });
      const callback = new URL("to.screencast.app://sharing/callback");
      callback.searchParams.set("code", code); callback.searchParams.set("state", body.state as string);
      return json({ callbackURL: callback.href });
    }
    if (route === "exchange") {
      const record = await readTicket(env, body.code, "connect", mode, now);
      if (!record || typeof body.codeVerifier !== "string" || !VERIFIER.test(body.codeVerifier) ||
          body.state !== record.ticket.state || await digest(body.codeVerifier) !== record.ticket.challenge) return denied();
      if (!await paidSession(stripe, env, record.ticket.session, mode) || !await consume(env, record)) return denied();
      return credentials(env, record.ticket.session, mode, now);
    }
    if (route === "token") {
      if (typeof body.sharingGrant !== "string") return denied();
      const grant = await open(body.sharingGrant, env.SERVICE_TOKEN_SECRET, mode, now);
      if (!grant || !await paidSession(stripe, env, grant.session, mode)) return denied();
      return credentials(env, grant.session, mode, now);
    }
    if (route === "restore") {
      if (!isPurchaseEmailConfigured(env)) return json({ error: "Purchase recovery is temporarily unavailable." }, 503);
      if (typeof body.email !== "string" || body.email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email) ||
          !validBinding(body, true)) return json({ error: "Enter the email used at checkout." }, 400);
      const email = body.email.trim().toLowerCase();
      const emailLimit = await env.SIGN_LIMITER.limit({ key: `website-restore-email:${await digest(email)}` });
      if (!emailLimit.success) return json({ sent: true });
      const found = await findPurchase(stripe, env, email, mode);
      if (found) {
        const token = await makeTicket(env, { v: 1, purpose: "restore", session: found.session, mode, exp: now + SHORT_TTL });
        const restore = new URL("/connect-sharing.html", site);
        restore.searchParams.set("restore", token);
        if (body.codeChallenge) { restore.searchParams.set("code_challenge", body.codeChallenge as string); restore.searchParams.set("state", body.state as string); }
        await (dependencies.sendEmail || sendPurchaseRestoreEmail)(env, found.recipient, restore.href);
      }
      return json({ sent: true });
    }
    const record = await readTicket(env, body.token, "restore", mode, now);
    if (!record || !await paidSession(stripe, env, record.ticket.session, mode) || !await consume(env, record)) return denied();
    return json({ paid: true }, 200, { "Set-Cookie": `__Host-screencast-purchase=${encodeURIComponent(record.ticket.session)}; Path=/; Max-Age=2592000; HttpOnly; SameSite=Lax; Secure` });
  } catch (error) {
    (dependencies.logger || console).error("Website purchase connection failed:", (error as { type?: string; name?: string })?.type || (error as Error)?.name || "unknown");
    return json({ error: "Purchase connection is temporarily unavailable. Please try again." }, 503);
  }
}
