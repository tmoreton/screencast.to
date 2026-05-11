import { AwsClient } from "aws4fetch";

interface Env {
  R2_ACCOUNT_ID: string;
  R2_BUCKET: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_PUB_HOST: string;
  APP_SECRET: string;
  SIGN_LIMITER: { limit: (opts: { key: string }) => Promise<{ success: boolean }> };
}

interface SignRequestBody {
  ext?: string;
}

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Screencast-Auth",
};

const BRAND = "Screencast.to";

// Google Analytics 4 Measurement ID. Replace G-XXXXXXXXXX with the real one
// from https://analytics.google.com → Admin → Data Streams → your web stream.
const GA_MEASUREMENT_ID = "G-XXXXXXXXXX";

const GA_SNIPPET = `
<script async src="https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', '${GA_MEASUREMENT_ID}');
</script>`;

// Inline SVG favicon — red squircle + white ring + white record dot.
// Mirrors the macOS app icon and the onboarding brand mark.
// All `"` inside the SVG are %22-encoded so the data URI doesn't break out
// of the HTML attribute it's interpolated into.
const FAVICON_HREF = "data:image/svg+xml," +
  "<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 32 32%22>" +
  "<defs><linearGradient id=%22g%22 x1=%220%22 y1=%220%22 x2=%2232%22 y2=%2232%22 gradientUnits=%22userSpaceOnUse%22>" +
  "<stop offset=%220%22 stop-color=%22%23f64d4d%22/>" +
  "<stop offset=%221%22 stop-color=%22%23d12d2d%22/>" +
  "</linearGradient></defs>" +
  "<rect x=%222%22 y=%222%22 width=%2228%22 height=%2228%22 rx=%227%22 fill=%22url(%23g)%22/>" +
  "<circle cx=%2216%22 cy=%2216%22 r=%229.5%22 fill=%22none%22 stroke=%22%23fff%22 stroke-opacity=%220.95%22 stroke-width=%222.5%22/>" +
  "<circle cx=%2216%22 cy=%2216%22 r=%225.5%22 fill=%22%23fff%22/>" +
  "</svg>";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    const url = new URL(request.url);

    if (url.pathname === "/sign" && request.method === "POST") {
      return handleSign(request, env);
    }
    if (url.pathname.startsWith("/v/") && request.method === "GET") {
      return handleViewer(url, env);
    }
    if (url.pathname.startsWith("/download/") && request.method === "GET") {
      return handleDownload(url, env);
    }
    if (url.pathname === "/" && request.method === "GET") {
      return new Response(renderHome(), {
        status: 200,
        headers: { "Content-Type": "text/html; charset=utf-8", ...CORS },
      });
    }
    if (url.pathname === "/privacy" && request.method === "GET") {
      return new Response(renderPrivacy(), {
        status: 200,
        headers: { "Content-Type": "text/html; charset=utf-8", ...CORS },
      });
    }
    return new Response("Not found", { status: 404, headers: CORS });
  },
};

async function handleSign(request: Request, env: Env): Promise<Response> {
  // Shared-secret auth.
  const provided = request.headers.get("X-Screencast-Auth") ?? "";
  if (!env.APP_SECRET || !timingSafeEqual(provided, env.APP_SECRET)) {
    return new Response("Unauthorized", { status: 401, headers: CORS });
  }

  // Per-IP rate limit.
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const { success } = await env.SIGN_LIMITER.limit({ key: ip });
  if (!success) {
    return new Response("Too many requests", { status: 429, headers: CORS });
  }

  let body: SignRequestBody = {};
  try {
    body = (await request.json()) as SignRequestBody;
  } catch {
    // empty body OK
  }
  const ext = sanitizeExt(body.ext ?? "mov");
  const id = generateShortId();
  const key = `recordings/${id}.${ext}`;

  const r2 = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
  });

  const endpoint = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET}/${key}`;
  const signed = await r2.sign(
    new Request(`${endpoint}?X-Amz-Expires=900`, { method: "PUT" }),
    { aws: { signQuery: true } }
  );

  const origin = new URL(request.url).origin;
  const publicUrl = `${origin}/v/${id}.${ext}`;

  return new Response(
    JSON.stringify({ uploadUrl: signed.url, publicUrl }),
    { status: 200, headers: { "Content-Type": "application/json", ...CORS } }
  );
}

function handleViewer(url: URL, env: Env): Response {
  const filename = url.pathname.slice("/v/".length);
  if (!/^[a-zA-Z0-9]{6,16}\.[a-zA-Z0-9]+$/.test(filename)) {
    return new Response("Not found", { status: 404, headers: CORS });
  }
  const videoUrl = `https://${normalizeHost(env.R2_PUB_HOST)}/recordings/${filename}`;
  return new Response(renderViewer(videoUrl), {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8", ...CORS },
  });
}

function handleDownload(url: URL, env: Env): Response {
  const file = url.pathname.slice("/download/".length);
  if (!/^[a-zA-Z0-9._-]+$/.test(file) || file.startsWith(".")) {
    return new Response("Not found", { status: 404, headers: CORS });
  }
  const target = `https://${normalizeHost(env.R2_PUB_HOST)}/downloads/${file}`;
  return Response.redirect(target, 302);
}

function normalizeHost(host: string): string {
  return host.replace(/^https?:\/\//i, "").replace(/\/+$/, "");
}

function sanitizeExt(ext: string): string {
  return ext.replace(/[^a-zA-Z0-9]/g, "").slice(0, 8) || "mov";
}

// 10-char URL-safe random ID. 62^10 ≈ 8.4 × 10^17 combinations — collision
// risk is negligible for 24h-lifetime recordings.
function generateShortId(): string {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = new Uint8Array(10);
  crypto.getRandomValues(bytes);
  let out = "";
  for (const b of bytes) out += alphabet[b % 62];
  return out;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function escapeHtml(s: string): string {
  const map: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  };
  return s.replace(/[&<>"']/g, (c) => map[c]!);
}

function renderViewer(videoUrl: string): string {
  const safe = escapeHtml(videoUrl);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#000000">
<title>${BRAND}</title>
<meta name="description" content="A screencast shared via Screencast.to. Free macOS menu-bar app — record your screen and share a link.">
<link rel="icon" href="${FAVICON_HREF}">

<!-- Open Graph / Twitter — same brand image for now -->
<meta property="og:site_name" content="Screencast.to">
<meta property="og:title" content="Watch this screencast">
<meta property="og:description" content="Shared via Screencast.to — record your screen, share a link. Always free.">
<meta property="og:type" content="video.other">
<meta property="og:image" content="https://screencast.to/download/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Watch this screencast">
<meta name="twitter:description" content="Shared via Screencast.to.">
<meta name="twitter:image" content="https://screencast.to/download/og.png">
${GA_SNIPPET}
<style>
  :root { --accent: #ef4444; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { height: 100dvh; width: 100dvw; background: #000; color: #fff; overflow: hidden;
    font: 14px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; }
  .stage { position: fixed; inset: 0; display: grid; place-items: center; cursor: default; }
  video {
    display: block;
    max-width: 100dvw;
    max-height: 100dvh;
    width: auto;
    height: auto;
    object-fit: contain;
    background: #000;
  }

  .overlay { position: fixed; left: 0; right: 0; padding: 16px 18px; display: flex;
    align-items: center; justify-content: space-between; gap: 10px; pointer-events: none;
    transition: opacity 220ms ease; z-index: 10; }
  .overlay > * { pointer-events: auto; }
  .overlay.top { top: 0;
    background: linear-gradient(to bottom, rgba(0,0,0,0.6), rgba(0,0,0,0)); }
  .stage.idle .overlay { opacity: 0; }

  .brand { display: flex; align-items: center; gap: 9px; min-width: 0;
    text-shadow: 0 1px 8px rgba(0,0,0,0.55); }
  .brand .dot { width: 10px; height: 10px; background: var(--accent); border-radius: 50%;
    box-shadow: 0 0 14px var(--accent); flex: 0 0 auto; }
  .brand h1 { font-size: 15px; font-weight: 600; letter-spacing: -0.01em;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .actions { display: flex; gap: 8px; flex-shrink: 0; }
  .chip { appearance: none; color: #fff; font: inherit; cursor: pointer; text-decoration: none;
    display: inline-flex; align-items: center; gap: 6px;
    padding: 8px 13px; border-radius: 999px;
    background: rgba(20, 20, 22, 0.55);
    border: 1px solid rgba(255,255,255,0.14);
    backdrop-filter: blur(14px) saturate(140%);
    -webkit-backdrop-filter: blur(14px) saturate(140%);
    transition: background 160ms ease, transform 160ms ease; }
  .chip:hover { background: rgba(40, 40, 44, 0.7); }
  .chip:active { transform: scale(0.97); }
  .chip svg { width: 14px; height: 14px; stroke: currentColor; fill: none; stroke-width: 2;
    stroke-linecap: round; stroke-linejoin: round; }

  /* Bottom overlay — watermark CTA + auto-delete chip */
  .overlay.bottom { bottom: 0;
    background: linear-gradient(to top, rgba(0,0,0,0.6), rgba(0,0,0,0));
    padding-top: 28px;
  }
  .watermark {
    display: inline-flex; align-items: center; gap: 7px;
    color: rgba(255,255,255,0.75); text-decoration: none;
    font-size: 12px; font-weight: 500;
    text-shadow: 0 1px 6px rgba(0,0,0,0.55);
    transition: color 140ms ease;
  }
  .watermark:hover { color: #fff; }
  .watermark .dot { width: 7px; height: 7px; border-radius: 50%;
    background: var(--accent); box-shadow: 0 0 8px var(--accent); }
  .watermark .mark { font-weight: 600; }

  .ttl {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 6px 11px; border-radius: 999px;
    background: rgba(20, 20, 22, 0.55);
    border: 1px solid rgba(255,255,255,0.14);
    backdrop-filter: blur(14px) saturate(140%);
    -webkit-backdrop-filter: blur(14px) saturate(140%);
    color: rgba(255,255,255,0.75);
    font-size: 11px; font-weight: 500;
  }
  .ttl svg { width: 11px; height: 11px; stroke: currentColor; fill: none;
    stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }

  /* Expired / 404 state */
  #expired { display: none; padding: 40px 28px; max-width: 460px; text-align: center; }
  .stage.expired #expired { display: block; }
  .stage.expired video,
  .stage.expired .overlay { display: none; }
  #expired .icon {
    width: 64px; height: 64px; border-radius: 16px;
    margin: 0 auto 22px;
    background: rgba(239,68,68,0.12); color: var(--accent);
    display: grid; place-items: center;
  }
  #expired .icon svg { width: 28px; height: 28px; stroke: currentColor; fill: none;
    stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
  #expired h2 { font-size: 22px; font-weight: 600; letter-spacing: -0.01em; margin-bottom: 10px; }
  #expired p { color: rgba(255,255,255,0.6); font-size: 14px; line-height: 1.55; margin-bottom: 24px; }
  #expired a.btn {
    display: inline-flex; align-items: center; gap: 8px;
    padding: 12px 20px; border-radius: 10px;
    background: var(--accent); color: #fff; font-size: 14px; font-weight: 600;
    text-decoration: none;
    box-shadow: 0 8px 24px -8px rgba(239,68,68,0.6);
  }
  #expired a.btn:hover { background: #f56565; }

  /* Compact layout on narrow viewports */
  @media (max-width: 520px) {
    .overlay { padding: 12px 14px; }
    .overlay.bottom { padding-top: 24px; }
    .chip { padding: 8px 10px; }
    .chip span { display: none; }
    .brand h1 { font-size: 14px; }
    .ttl { font-size: 10px; padding: 5px 9px; }
  }
</style>
</head>
<body>
<div class="stage" id="stage">
  <video id="player" src="${safe}" controls preload="metadata" playsinline></video>

  <div class="overlay top">
    <div class="brand"><span class="dot"></span><h1>${BRAND}</h1></div>
    <div class="actions">
      <button class="chip" id="copyBtn" type="button" aria-label="Copy link">
        <svg viewBox="0 0 24 24"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>
        <span>Copy link</span>
      </button>
      <a class="chip" href="${safe}" download aria-label="Download">
        <svg viewBox="0 0 24 24"><path d="M12 3v12"/><path d="M7 10l5 5 5-5"/><path d="M5 21h14"/></svg>
        <span>Download</span>
      </a>
    </div>
  </div>

  <div class="overlay bottom">
    <a class="watermark" href="https://screencast.to/" target="_blank" rel="noopener">
      <span class="dot"></span>
      Made with <span class="mark">${BRAND}</span>
    </a>
    <span class="ttl" title="Recordings auto-delete after 24 hours.">
      <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg>
      Auto-deletes in 24h
    </span>
  </div>

  <div id="expired">
    <div class="icon">
      <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg>
    </div>
    <h2>This recording is gone.</h2>
    <p>It either expired (recordings auto-delete after 24 hours) or the link is wrong. Recordings on ${BRAND} are temporary by design — share confidently and move on.</p>
    <a class="btn" href="https://screencast.to/">Make your own →</a>
  </div>
</div>
<script>
  const stage = document.getElementById('stage');
  const player = document.getElementById('player');
  const copyBtn = document.getElementById('copyBtn');

  // Auto-hide overlays after idle while playing.
  let idleTimer;
  function poke() {
    stage.classList.remove('idle');
    clearTimeout(idleTimer);
    if (!player.paused) {
      idleTimer = setTimeout(() => stage.classList.add('idle'), 2200);
    }
  }
  ['mousemove','mousedown','touchstart','keydown'].forEach(e => window.addEventListener(e, poke));
  player.addEventListener('play', poke);
  player.addEventListener('pause', () => { stage.classList.remove('idle'); clearTimeout(idleTimer); });
  poke();

  // Copy-link feedback.
  copyBtn.addEventListener('click', () => {
    navigator.clipboard.writeText(location.href).then(() => {
      const label = copyBtn.querySelector('span');
      const orig = label.textContent;
      label.textContent = 'Copied!';
      setTimeout(() => { label.textContent = orig; }, 1500);
    });
  });

  // Expired / 404 fallback: the <video> element fires 'error' when the
  // underlying R2 object is gone (lifecycle-deleted or wrong link).
  function showExpired() { stage.classList.add('expired'); }
  player.addEventListener('error', showExpired);
  // Some browsers fire error on the <source> not the <video>; also handle
  // the case where metadata never loads in a reasonable time.
  setTimeout(() => {
    if (player.readyState === 0 && !player.error && !stage.classList.contains('expired')) {
      // Still nothing; probe the URL ourselves to distinguish 404 from slow CDN.
      fetch(player.src, { method: 'HEAD' })
        .then(r => { if (!r.ok) showExpired(); })
        .catch(() => {});
    }
  }, 6000);
</script>
</body>
</html>`;
}

function renderPrivacy(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#0a0c10">
<title>Privacy — ${BRAND}</title>
<meta name="description" content="Screencast.to's privacy policy. Plain language, no tricks.">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://screencast.to/privacy">
<link rel="icon" href="${FAVICON_HREF}">
${GA_SNIPPET}
<style>
  :root {
    --bg: #0a0c10;
    --bg-elev: #13161c;
    --border: #1f232c;
    --text: #e8eaed;
    --text-2: #b8bcc6;
    --muted: #8b909a;
    --accent: #ef4444;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html { scroll-behavior: smooth; }
  body {
    background: var(--bg); color: var(--text); min-height: 100vh;
    font: 16px/1.65 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  nav {
    display: flex; align-items: center; justify-content: space-between;
    padding: 18px 28px;
    border-bottom: 1px solid rgba(255,255,255,0.04);
  }
  .brand { display: flex; align-items: center; gap: 9px; color: var(--text);
    font-weight: 600; letter-spacing: -0.01em; }
  .brand .dot { width: 10px; height: 10px; border-radius: 50%;
    background: var(--accent); box-shadow: 0 0 14px var(--accent); }
  main { max-width: 720px; margin: 0 auto; padding: 56px 24px 80px; }
  h1 { font-size: 36px; letter-spacing: -0.02em; margin-bottom: 8px; }
  .lede { color: var(--text-2); margin-bottom: 8px; font-size: 17px; }
  .updated { color: var(--muted); font-size: 12px; margin-bottom: 40px; }
  h2 { font-size: 18px; letter-spacing: -0.01em; margin-top: 36px; margin-bottom: 10px; }
  p, li { color: var(--text-2); }
  p { margin-bottom: 12px; }
  ul { padding-left: 22px; margin-bottom: 12px; }
  li { margin-bottom: 6px; }
  .tldr {
    background: var(--bg-elev);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 18px 22px;
    margin: 24px 0 8px;
  }
  .tldr h2 { margin-top: 0; color: var(--text); }
  code { background: rgba(255,255,255,0.06); padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
  footer { border-top: 1px solid var(--border); padding: 24px; color: var(--muted); font-size: 13px; text-align: center; }
  footer a { color: var(--text-2); }
</style>
</head>
<body>
<nav>
  <a class="brand" href="/"><span class="dot"></span><span>${BRAND}</span></a>
  <a href="/" style="color: var(--text-2); font-size: 14px;">← Home</a>
</nav>
<main>
  <h1>Privacy</h1>
  <p class="lede">Plain language, no tricks.</p>
  <p class="updated">Last updated: ${new Date().toISOString().slice(0, 10)}</p>

  <div class="tldr">
    <h2>TL;DR</h2>
    <p>${BRAND} records your screen locally on your Mac, uploads the file to our storage, and gives you a shareable link. Anyone with the link can watch. Recordings auto-delete after 24 hours. We don't watch, mine, or sell your recordings. We track basic anonymous website analytics — nothing tied to specific recordings.</p>
  </div>

  <h2>What we collect</h2>
  <ul>
    <li><strong>Your screen recordings</strong>, only when you press Record. The file is stored on Cloudflare R2 (encrypted at rest) and accessible via a randomly-generated link.</li>
    <li><strong>Anonymous website analytics</strong> — page views, country, browser — via Google Analytics. Standard cookie-based tracking. No personal info.</li>
    <li><strong>IP address</strong> on each recording-upload request, used only for short-window rate limiting (10 uploads / minute / IP). Not persisted.</li>
  </ul>
  <p>That's it. We don't collect your name, email, or any account info — there are no accounts.</p>

  <h2>Where your recordings live</h2>
  <p>Recordings are stored in a Cloudflare R2 bucket controlled by ${BRAND}. They are NOT publicly listed — only someone who has your specific share URL (which contains a random 10-character ID) can access the recording.</p>

  <h2>Auto-deletion</h2>
  <p>Every recording is deleted automatically <strong>within 24–48 hours</strong> of upload via a Cloudflare R2 lifecycle rule. After that, the share link returns a "Not Found" page. We can't recover deleted recordings.</p>

  <h2>Who can see your recording</h2>
  <p>Anyone who has the share URL can watch the recording until it auto-deletes. Treat the URL like a password — if it's shared publicly (e.g., on Twitter), the recording is effectively public. The viewer page doesn't require login.</p>

  <h2>Third parties</h2>
  <ul>
    <li><strong>Cloudflare</strong> — hosts the worker, stores recordings on R2, terminates TLS. <a href="https://www.cloudflare.com/privacypolicy/" target="_blank" rel="noopener">Their privacy policy</a>.</li>
    <li><strong>Google Analytics</strong> — anonymous traffic stats for the website (not the recordings). <a href="https://policies.google.com/privacy" target="_blank" rel="noopener">Their privacy policy</a>.</li>
  </ul>
  <p>We don't share recordings or data with anyone else.</p>

  <h2>Cookies</h2>
  <p>The website uses Google Analytics cookies (<code>_ga</code>, <code>_ga_*</code>) for anonymous traffic analytics. Block them in your browser if you prefer — the site works without them. The Mac app itself uses no cookies.</p>

  <h2>Your rights</h2>
  <p>You can delete a recording immediately by closing its share URL (the lifecycle rule will sweep it within 24h). Since we don't have accounts, there's no profile to delete.</p>

  <h2>Abuse</h2>
  <p>If you find a recording that should be removed (illegal content, harassment, etc.), email the operator. Recordings can be deleted manually within the bucket — they will be removed within 24 hours regardless.</p>

  <h2>Changes</h2>
  <p>This policy may be updated as the product evolves. The "Last updated" date at the top reflects the current version.</p>
</main>
<footer>
  <a href="/">${BRAND}</a> · <a href="/privacy">Privacy</a>
</footer>
</body>
</html>`;
}

function renderHome(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#0a0c10">
<title>${BRAND} — Record your screen, share a link</title>
<meta name="description" content="A tiny macOS menu-bar app. Hit record, get a shareable link the moment you stop. Always free. Recordings auto-delete after 24 hours.">
<meta name="keywords" content="screen recorder, mac screen recording, loom alternative, free screen recorder, macOS, share screen recording, screencast">
<meta name="author" content="Screencast.to">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://screencast.to/">
<link rel="icon" href="${FAVICON_HREF}">

<!-- Open Graph (Facebook, LinkedIn, iMessage, Slack) -->
<meta property="og:site_name" content="Screencast.to">
<meta property="og:title" content="Screencast.to — Record your screen, share a link">
<meta property="og:description" content="A tiny macOS menu-bar app. Hit record, get a shareable link the moment you stop. Always free.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://screencast.to/">
<meta property="og:image" content="https://screencast.to/download/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Screencast.to — record your screen, share a link">
<meta property="og:locale" content="en_US">

<!-- Twitter / X -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Screencast.to — Record your screen, share a link">
<meta name="twitter:description" content="A tiny macOS menu-bar app. Hit record, get a shareable link. Always free.">
<meta name="twitter:image" content="https://screencast.to/download/og.png">

${GA_SNIPPET}
<style>
  :root {
    --bg: #0a0c10;
    --bg-elev: #13161c;
    --border: #1f232c;
    --border-hi: #2a2f3a;
    --text: #e8eaed;
    --text-2: #b8bcc6;
    --muted: #8b909a;
    --accent: #ef4444;
    --accent-hi: #f56565;
    --grad: radial-gradient(1200px 600px at 50% -10%, rgba(239,68,68,0.18), transparent 60%);
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html { scroll-behavior: smooth; }
  body {
    background: var(--bg);
    background-image: var(--grad);
    background-attachment: fixed;
    color: var(--text);
    font: 16px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
    min-height: 100vh;
    -webkit-font-smoothing: antialiased;
  }
  a { color: inherit; text-decoration: none; }
  ::selection { background: var(--accent); color: #fff; }

  nav {
    position: sticky; top: 0; z-index: 50;
    display: flex; align-items: center; justify-content: space-between;
    padding: 18px 28px;
    backdrop-filter: blur(14px) saturate(140%);
    -webkit-backdrop-filter: blur(14px) saturate(140%);
    background: rgba(10, 12, 16, 0.6);
    border-bottom: 1px solid rgba(255,255,255,0.04);
  }
  .brand { display: flex; align-items: center; gap: 9px; font-weight: 600; letter-spacing: -0.01em; }
  .brand .dot {
    width: 10px; height: 10px; border-radius: 50%;
    background: var(--accent); box-shadow: 0 0 14px var(--accent);
  }
  nav .links { display: flex; align-items: center; gap: 8px; }
  nav .links a { color: var(--text-2); font-size: 14px; padding: 8px 12px; border-radius: 8px; transition: color 140ms ease, background 140ms ease; }
  nav .links a:hover { color: var(--text); background: rgba(255,255,255,0.05); }

  .btn {
    display: inline-flex; align-items: center; gap: 8px;
    padding: 10px 16px;
    border-radius: 10px;
    font-size: 14px; font-weight: 600;
    border: 1px solid var(--border);
    background: var(--bg-elev);
    color: var(--text);
    cursor: pointer;
    transition: transform 120ms ease, background 140ms ease, border-color 140ms ease;
  }
  .btn:hover { background: #1a1d24; border-color: var(--border-hi); }
  .btn:active { transform: scale(0.98); }
  .btn-primary {
    background: var(--accent); border-color: var(--accent); color: #fff;
    box-shadow: 0 6px 24px -8px rgba(239,68,68,0.6);
  }
  .btn-primary:hover { background: var(--accent-hi); border-color: var(--accent-hi); }
  .btn-lg { padding: 14px 22px; font-size: 15px; border-radius: 12px; }
  .btn svg { width: 14px; height: 14px; }

  main { max-width: 1080px; margin: 0 auto; padding: 0 24px; }

  .hero { text-align: center; padding: 96px 0 80px; }
  .hero .eyebrow {
    display: inline-block;
    font-size: 12px; font-weight: 600;
    color: var(--accent); letter-spacing: 0.06em; text-transform: uppercase;
    padding: 6px 12px; border-radius: 999px;
    background: rgba(239,68,68,0.1); border: 1px solid rgba(239,68,68,0.25);
    margin-bottom: 24px;
  }
  .hero h1 {
    font-size: clamp(40px, 7vw, 76px);
    line-height: 1.02; letter-spacing: -0.03em; font-weight: 700;
    margin-bottom: 20px;
  }
  .hero h1 .accent { color: var(--accent); }
  .hero p { font-size: clamp(16px, 1.8vw, 19px); color: var(--text-2); max-width: 620px; margin: 0 auto 36px; }
  .hero .cta { display: inline-flex; flex-direction: column; align-items: center; gap: 10px; }
  .hero .cta .note { font-size: 12px; color: var(--muted); }

  /* Mock player preview */
  .preview {
    margin: 56px auto 0;
    max-width: 880px;
    aspect-ratio: 16 / 10;
    border-radius: 14px;
    background:
      linear-gradient(135deg, rgba(255,255,255,0.04), rgba(255,255,255,0)),
      linear-gradient(180deg, #1c2029, #0c0e13);
    border: 1px solid var(--border-hi);
    box-shadow: 0 40px 80px -20px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.02) inset;
    position: relative;
    overflow: hidden;
  }
  .preview .chrome {
    display: flex; gap: 6px;
    padding: 12px 14px;
    border-bottom: 1px solid rgba(255,255,255,0.05);
  }
  .preview .chrome span { width: 11px; height: 11px; border-radius: 50%; background: #2a2f3a; }
  .preview .chrome span:nth-child(1) { background: #ff5f57; }
  .preview .chrome span:nth-child(2) { background: #febc2e; }
  .preview .chrome span:nth-child(3) { background: #28c840; }
  .preview .body { position: absolute; inset: 38px 0 0; overflow: hidden; }

  /* Mock app being recorded — full-width dashboard. */
  .preview .mock { height: 100%; width: 100%; }
  .preview .mock-text { height: 8px; border-radius: 3px; background: rgba(255,255,255,0.10); width: 100%; }
  .preview .w35 { width: 35%; } .preview .w40 { width: 40%; }
  .preview .w45 { width: 45%; } .preview .w50 { width: 50%; }
  .preview .w55 { width: 55%; } .preview .w60 { width: 60%; }
  .preview .w65 { width: 65%; } .preview .w75 { width: 75%; }
  .preview .w85 { width: 85%; }
  .preview .mock-main {
    padding: 18px 32px 22px;
    display: flex; flex-direction: column; gap: 14px;
    min-width: 0;
    height: 100%;
    width: 100%;
  }
  /* Toolbar at top of main */
  .preview .mock-toolbar {
    display: flex; align-items: center; gap: 10px;
    padding-bottom: 12px;
    border-bottom: 1px solid rgba(255,255,255,0.04);
  }
  .preview .mock-avatar {
    width: 26px; height: 26px; border-radius: 50%;
    background: linear-gradient(135deg, #4a5060, #1a1d24);
    flex-shrink: 0;
  }
  .preview .mock-h {
    height: 14px; width: 36%;
    background: rgba(255,255,255,0.18);
    border-radius: 4px;
  }
  .preview .mock-btn {
    height: 22px; border-radius: 6px;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.06);
    flex-shrink: 0;
  }
  .preview .mock-btn.w40px { width: 40px; }
  .preview .mock-btn.w52px { width: 52px; }
  .preview .mock-btn--accent {
    background: rgba(239,68,68,0.22);
    border-color: rgba(239,68,68,0.28);
    width: 36px;
  }

  /* Stat cards */
  .preview .mock-cards {
    display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px;
  }
  .preview .mock-card {
    height: 104px;
    background: rgba(255,255,255,0.05);
    border: 1px solid rgba(255,255,255,0.05);
    border-radius: 12px;
    padding: 14px;
    display: flex; flex-direction: column; gap: 10px;
    justify-content: space-between;
  }
  .preview .mock-card .label { height: 8px; width: 55%; background: rgba(255,255,255,0.12); border-radius: 4px; }
  .preview .mock-card .num   { height: 22px; width: 45%; background: rgba(255,255,255,0.34); border-radius: 5px; }
  .preview .mock-card .trend { height: 7px; width: 70%; background: rgba(94,234,123,0.50); border-radius: 4px; }
  .preview .mock-card.is-down .trend { background: rgba(239,68,68,0.50); }

  /* Mini bar chart — fills remaining vertical space */
  .preview .mock-chart {
    flex: 1;
    min-height: 100px;
    display: flex; align-items: flex-end; gap: 8px;
    padding: 14px;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.04);
    border-radius: 12px;
  }
  .preview .mock-bar {
    flex: 1; border-radius: 3px 3px 0 0;
    background: linear-gradient(to top, rgba(239,68,68,0.55), rgba(239,68,68,0.18));
  }
  .preview .mock-bar.muted {
    background: linear-gradient(to top, rgba(255,255,255,0.18), rgba(255,255,255,0.06));
  }

  /* Bottom rows */
  .preview .mock-rows {
    display: flex; flex-direction: column; gap: 10px;
  }
  .preview .mock-row-line {
    display: flex; align-items: center; gap: 12px;
  }
  .preview .mock-row-line .pill-tag {
    width: 36px; height: 14px; border-radius: 999px;
    background: rgba(239,68,68,0.22);
    flex-shrink: 0;
  }
  .preview .mock-row-line .pill-tag.gray { background: rgba(255,255,255,0.12); }
  .preview .mock-row-line .mock-text { height: 10px; }

  /* Recording overlays */
  .preview .pill {
    position: absolute;
    top: 16px; left: 50%; transform: translateX(-50%);
    background: rgba(20,20,22,0.85);
    backdrop-filter: blur(14px);
    border: 1px solid rgba(255,255,255,0.14);
    color: #fff;
    padding: 8px 14px; border-radius: 999px;
    display: inline-flex; align-items: center; gap: 8px;
    font-size: 13px; font-weight: 600;
    box-shadow: 0 6px 20px rgba(0,0,0,0.4);
  }
  .preview .pill .reddot {
    width: 8px; height: 8px; border-radius: 50%; background: var(--accent);
    box-shadow: 0 0 10px var(--accent);
    animation: pulse 1s infinite alternate;
  }
  @keyframes pulse { from { opacity: 1; } to { opacity: 0.3; } }

  .preview .bubble {
    position: absolute; bottom: 18px; right: 18px;
    width: 84px; height: 84px; border-radius: 50%;
    background: linear-gradient(135deg, #5e6478 0%, #1f2229 100%);
    border: 3px solid rgba(255,255,255,0.92);
    box-shadow: 0 10px 28px rgba(0,0,0,0.5);
    overflow: hidden;
    display: grid; place-items: center;
  }
  .preview .bubble svg { width: 100%; height: 100%; }

  /* Sections */
  section.block { padding: 80px 0; }
  section.block .lede { text-align: center; max-width: 640px; margin: 0 auto 56px; }
  section.block .lede h2 {
    font-size: clamp(28px, 4vw, 40px); letter-spacing: -0.02em; font-weight: 700;
    margin-bottom: 12px;
  }
  section.block .lede p { color: var(--text-2); font-size: 17px; }

  .features {
    display: grid; gap: 16px;
    grid-template-columns: repeat(3, 1fr);
  }
  @media (max-width: 880px) {
    .features { grid-template-columns: repeat(2, 1fr); }
  }
  @media (max-width: 560px) {
    .features { grid-template-columns: 1fr; }
  }
  .card {
    background: var(--bg-elev);
    border: 1px solid var(--border);
    border-radius: 14px;
    padding: 24px;
    transition: border-color 140ms ease, transform 140ms ease;
  }
  .card:hover { border-color: var(--border-hi); transform: translateY(-2px); }
  .card .icon {
    width: 36px; height: 36px;
    display: inline-flex; align-items: center; justify-content: center;
    border-radius: 10px;
    background: rgba(239,68,68,0.12);
    color: var(--accent);
    margin-bottom: 14px;
  }
  .card .icon svg { width: 18px; height: 18px; stroke: currentColor; fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
  .card h3 { font-size: 16px; margin-bottom: 6px; letter-spacing: -0.01em; }
  .card p { color: var(--muted); font-size: 14px; line-height: 1.55; }

  .steps {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 36px;
    max-width: 880px;
    margin: 0 auto;
  }
  .step { text-align: center; }
  .step .num {
    margin: 0 auto 16px;
    width: 36px; height: 36px;
    display: grid; place-items: center;
    border-radius: 50%;
    background: var(--accent); color: #fff;
    font-weight: 700; font-size: 14px;
    box-shadow: 0 6px 18px -6px rgba(239,68,68,0.55);
  }
  .step h3 { font-size: 16px; margin-bottom: 6px; letter-spacing: -0.01em; }
  .step p { color: var(--muted); font-size: 14px; line-height: 1.55; }

  @media (max-width: 720px) {
    .steps { grid-template-columns: 1fr; gap: 28px; }
  }

  .install {
    text-align: center; padding: 80px 24px;
    background: var(--bg-elev);
    border: 1px solid var(--border); border-radius: 16px;
    margin: 24px 0 80px;
  }
  .install h2 { font-size: clamp(26px, 3.5vw, 36px); letter-spacing: -0.02em; margin-bottom: 12px; }
  .install p { color: var(--text-2); margin-bottom: 24px; max-width: 480px; margin-left: auto; margin-right: auto; }
  .install .row { display: inline-flex; gap: 10px; flex-wrap: wrap; justify-content: center; }
  .install .note { display: block; margin-top: 14px; font-size: 12px; color: var(--muted); }

  footer {
    border-top: 1px solid var(--border);
    padding: 28px 24px;
    color: var(--muted);
    font-size: 13px;
    display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap;
  }
  footer a { color: var(--text-2); text-decoration: none; transition: color 140ms ease; }
  footer a:hover { color: var(--text); text-decoration: underline; }

  @media (max-width: 600px) {
    nav { padding: 14px 18px; }
    nav .links a:not(.btn) { display: none; }
    .hero { padding: 64px 0 56px; }
    section.block { padding: 56px 0; }
  }
</style>
</head>
<body>

<nav>
  <a class="brand" href="/">
    <span class="dot"></span>
    <span>${BRAND}</span>
  </a>
  <div class="links">
    <a href="#features">Features</a>
    <a href="#how">How it works</a>
    <a class="btn btn-primary" href="/download/screencast.dmg" download>Download</a>
  </div>
</nav>

<main>

  <section class="hero">
    <span class="eyebrow">macOS · Always free</span>
    <h1>Record your screen.<br><span class="accent">Share a link.</span></h1>
    <p>A tiny menu-bar app for macOS. Hit record, capture exactly what you want, and get a shareable link the moment you stop.</p>
    <div class="cta">
      <a class="btn btn-primary btn-lg" href="/download/screencast.dmg" download>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 3v12"/><path d="M7 10l5 5 5-5"/><path d="M5 21h14"/>
        </svg>
        Download for Mac
      </a>
      <span class="note">macOS 15+ · Apple Silicon and Intel</span>
    </div>

    <div class="preview" aria-hidden="true">
      <div class="chrome"><span></span><span></span><span></span></div>
      <div class="body">
        <div class="mock">
          <main class="mock-main">
            <div class="mock-toolbar">
              <div class="mock-avatar"></div>
              <div class="mock-h"></div>
              <div style="flex:1"></div>
              <div class="mock-btn w40px"></div>
              <div class="mock-btn w52px"></div>
              <div class="mock-btn mock-btn--accent"></div>
            </div>

            <div class="mock-cards">
              <div class="mock-card"><div class="label"></div><div class="num"></div><div class="trend"></div></div>
              <div class="mock-card"><div class="label"></div><div class="num"></div><div class="trend"></div></div>
              <div class="mock-card is-down"><div class="label"></div><div class="num"></div><div class="trend"></div></div>
            </div>

            <div class="mock-chart">
              <div class="mock-bar muted" style="height:32%"></div>
              <div class="mock-bar muted" style="height:48%"></div>
              <div class="mock-bar muted" style="height:38%"></div>
              <div class="mock-bar muted" style="height:62%"></div>
              <div class="mock-bar"        style="height:74%"></div>
              <div class="mock-bar"        style="height:56%"></div>
              <div class="mock-bar"        style="height:88%"></div>
              <div class="mock-bar"        style="height:70%"></div>
              <div class="mock-bar muted" style="height:42%"></div>
              <div class="mock-bar muted" style="height:54%"></div>
              <div class="mock-bar muted" style="height:36%"></div>
              <div class="mock-bar muted" style="height:48%"></div>
            </div>

            <div class="mock-rows">
              <div class="mock-row-line"><div class="pill-tag"></div><div class="mock-text w85"></div></div>
              <div class="mock-row-line"><div class="pill-tag gray"></div><div class="mock-text w65"></div></div>
              <div class="mock-row-line"><div class="pill-tag gray"></div><div class="mock-text w75"></div></div>
            </div>
          </main>
        </div>
        <div class="pill"><span class="reddot"></span>00:14 · recording</div>
        <div class="bubble">
          <svg viewBox="0 0 80 80">
            <circle cx="40" cy="30" r="13" fill="rgba(255,255,255,0.34)"/>
            <path d="M14 72 C14 56 26 50 40 50 C54 50 66 56 66 72 Z" fill="rgba(255,255,255,0.34)"/>
          </svg>
        </div>
      </div>
    </div>
  </section>

  <section class="block" id="features">
    <div class="lede">
      <h2>Built to ship things fast</h2>
      <p>Everything you need to capture and share. Nothing you don't.</p>
    </div>
    <div class="features">

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="14" rx="2"/><path d="M8 21h8"/><path d="M12 18v3"/></svg></div>
        <h3>Full screen, window, or region</h3>
        <p>Drag to select exactly the area you want to capture. Or grab the whole display in one click.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M7 19c1-2 3-3 5-3s4 1 5 3"/></svg></div>
        <h3>Camera bubble</h3>
        <p>Drop your face into the corner of the recording. Drag it anywhere, even mid-shoot.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><path d="M12 1v22"/><line x1="6" y1="6" x2="18" y2="6"/><path d="M9 12h6"/><path d="M9 18h6"/></svg></div>
        <h3>Mic + system audio</h3>
        <p>Capture your voice and whatever's playing on your Mac, in sync, on every recording.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><path d="M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 0 0-7.07-7.07l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 0 0 7.07 7.07l1.5-1.5"/></svg></div>
        <h3>Instant share link</h3>
        <p>Stop recording and the link is on your clipboard. Recipient watches in their browser — no app, no login.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg></div>
        <h3>Auto-deletes in 24h</h3>
        <p>Recordings expire automatically. Nothing lingers — share confidently and move on.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="14" rx="2"/><path d="M3 10h18"/><path d="M8 2v4"/><path d="M16 2v4"/></svg></div>
        <h3>Menu-bar native</h3>
        <p>No dock icon, no window clutter. One tiny status icon that gets out of your way until you need it.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><path d="M12 1v22"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg></div>
        <h3>Always free</h3>
        <p>No accounts, no plans, no upsells. Build a habit instead of a billing relationship.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><path d="M9 12l2 2 4-4"/><circle cx="12" cy="12" r="10"/></svg></div>
        <h3>No login for viewers</h3>
        <p>Recipients click your link and watch in their browser. No app to install, no signup, no friction.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><path d="M14 5l7 7-7 7"/><path d="M3 12h18"/></svg></div>
        <h3>Universal binary</h3>
        <p>Native on Apple Silicon and Intel. Built on ScreenCaptureKit — fast, battery-friendly, no helpers.</p>
      </div>

    </div>
  </section>

  <section class="block" id="how">
    <div class="lede">
      <h2>Three steps. Done.</h2>
      <p>From hitting record to having a link, in about five seconds.</p>
    </div>
    <div class="steps">
      <div class="step">
        <div class="num">1</div>
        <h3>Click the menu bar icon</h3>
        <p>Pick what to capture and the mic to use.</p>
      </div>
      <div class="step">
        <div class="num">2</div>
        <h3>Hit Start Recording</h3>
        <p>Drag the camera bubble anywhere on screen.</p>
      </div>
      <div class="step">
        <div class="num">3</div>
        <h3>Stop, copy, share</h3>
        <p>The link auto-uploads to your clipboard.</p>
      </div>
    </div>
  </section>

  <section class="install" id="install">
    <h2>Get ${BRAND}</h2>
    <p>Always free. Recordings live for 24 hours, then delete themselves. macOS 15+.</p>
    <div class="row">
      <a class="btn btn-primary btn-lg" href="/download/screencast.dmg">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 3v12"/><path d="M7 10l5 5 5-5"/><path d="M5 21h14"/>
        </svg>
        Download .dmg
      </a>
    </div>
    <span class="note">First launch will ask to grant Screen Recording, Camera, and Microphone in System Settings.</span>
  </section>

</main>

<footer>
  <span>© ${new Date().getFullYear()} ${BRAND}</span>
  <span>Recordings auto-delete after 24 hours · <a href="/privacy">Privacy</a></span>
</footer>

</body>
</html>`;
}
