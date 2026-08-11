import { BRAND, FAVICON_HREF, escapeHtml } from "./shared";

/** Share-link viewer at GET /v/<id>.<ext>. `videoUrl` is the canonical R2 URL. */
export function renderViewer(videoUrl: string): string {
  const safe = escapeHtml(videoUrl);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#000000">
<title>${BRAND}</title>
<meta name="description" content="A temporary screencast shared via Screencast.to. Free macOS menu-bar app — record locally, share a 24-hour link when you choose.">
<link rel="icon" href="${FAVICON_HREF}">

<!-- Open Graph / Twitter — same brand image for now -->
<meta property="og:site_name" content="Screencast.to">
<meta property="og:title" content="Watch this screencast">
<meta property="og:description" content="Shared via Screencast.to — temporary screen recordings for work.">
<meta property="og:type" content="video.other">
<meta property="og:image" content="https://screencast.to/download/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Watch this screencast">
<meta name="twitter:description" content="Temporary screen recordings for work.">
<meta name="twitter:image" content="https://screencast.to/download/og.png">
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
