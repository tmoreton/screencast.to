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
  "Access-Control-Allow-Headers": "Content-Type",
};

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
    if (url.pathname === "/" && request.method === "GET") {
      return new Response(renderHome(), {
        status: 200,
        headers: { "Content-Type": "text/html; charset=utf-8", ...CORS },
      });
    }
    return new Response("Not found", { status: 404, headers: CORS });
  },
};

async function handleSign(request: Request, env: Env): Promise<Response> {
  // Shared-secret auth.
  const provided = request.headers.get("X-Notloom-Auth") ?? "";
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
  const uuid = crypto.randomUUID();
  const key = `recordings/${uuid}.${ext}`;

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
  const publicUrl = `${origin}/v/${uuid}.${ext}`;

  return new Response(
    JSON.stringify({ uploadUrl: signed.url, publicUrl }),
    { status: 200, headers: { "Content-Type": "application/json", ...CORS } }
  );
}

function handleViewer(url: URL, env: Env): Response {
  const filename = url.pathname.slice("/v/".length);
  if (!/^[a-zA-Z0-9-]+\.[a-zA-Z0-9]+$/.test(filename)) {
    return new Response("Not found", { status: 404, headers: CORS });
  }
  const videoUrl = `https://${normalizeHost(env.R2_PUB_HOST)}/recordings/${filename}`;
  return new Response(renderViewer(videoUrl), {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8", ...CORS },
  });
}

function normalizeHost(host: string): string {
  return host.replace(/^https?:\/\//i, "").replace(/\/+$/, "");
}

function sanitizeExt(ext: string): string {
  return ext.replace(/[^a-zA-Z0-9]/g, "").slice(0, 8) || "mov";
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
<title>notloom</title>
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

  /* Compact layout on narrow viewports: drop the chip label, keep the icon. */
  @media (max-width: 520px) {
    .overlay { padding: 12px 14px; }
    .chip { padding: 8px 10px; }
    .chip span { display: none; }
    .brand h1 { font-size: 14px; }
  }
</style>
</head>
<body>
<div class="stage" id="stage">
  <video id="player" src="${safe}" controls preload="metadata" playsinline></video>
  <div class="overlay top">
    <div class="brand"><span class="dot"></span><h1>notloom</h1></div>
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
</div>
<script>
  const stage = document.getElementById('stage');
  const player = document.getElementById('player');
  const copyBtn = document.getElementById('copyBtn');

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

  copyBtn.addEventListener('click', () => {
    navigator.clipboard.writeText(location.href).then(() => {
      const label = copyBtn.querySelector('span');
      const orig = label.textContent;
      label.textContent = 'Copied!';
      setTimeout(() => { label.textContent = orig; }, 1500);
    });
  });
</script>
</body>
</html>`;
}

function renderHome(): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>notloom</title>
<style>body{font:15px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;background:#0b0d10;color:#e8eaed;display:grid;place-items:center;height:100vh;margin:0;text-align:center}h1{font-size:32px;margin-bottom:8px}p{color:#8b909a}</style>
</head><body><div><h1>notloom</h1><p>Screen recordings, shared via Cloudflare R2.</p></div></body></html>`;
}
