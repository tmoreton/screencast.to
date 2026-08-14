import { BRAND, DOWNLOAD_URL, FAVICON_HREF, GA_SNIPPET, GITHUB_URL, OG_IMAGE_URL, THEME_SCRIPT } from "./shared";

/** Landing page at GET /. */
export function renderHome(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#fbfaee" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#08090b" media="(prefers-color-scheme: dark)">
<title>${BRAND} - Local-first Mac screen recorder</title>
<meta name="description" content="Screencast.to is an open-source macOS menu-bar recorder. Record locally, then share an optional expiring link. No accounts, no permanent video library.">
<meta name="keywords" content="screen recorder, mac screen recording, loom alternative, free screen recorder, open source screen recorder, macOS, temporary video link">
<meta name="author" content="Screencast.to">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://screencast.to/">
<link rel="icon" href="${FAVICON_HREF}">

<meta property="og:site_name" content="Screencast.to">
<meta property="og:title" content="Screencast.to - Local-first Mac screen recorder">
<meta property="og:description" content="Record on your Mac. Share an expiring link only when you choose. Open source, local first, no accounts.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://screencast.to/">
<meta property="og:image" content="${OG_IMAGE_URL}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Screencast.to landing page">
<meta property="og:locale" content="en_US">

<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Screencast.to - Local-first Mac screen recorder">
<meta name="twitter:description" content="A tiny open-source Mac recorder for local captures and optional expiring share links.">
<meta name="twitter:image" content="${OG_IMAGE_URL}">

${GA_SNIPPET}
${THEME_SCRIPT}
<style>
  :root {
    color-scheme: light;
    --bg: #fbfaee;
    --bg-2: #f1f0e2;
    --surface: #fffff8;
    --surface-soft: #f6f5e8;
    --ink: #141414;
    --ink-soft: #3f403d;
    --muted: #707066;
    --line: rgba(20,20,20,0.14);
    --line-strong: rgba(20,20,20,0.24);
    --accent: #ff473f;
    --accent-strong: #d9302a;
    --accent-soft: #ffe0dc;
    --lavender: #ecd7ff;
    --sage: #dff4dc;
    --blue: #dbeaff;
    --button-text: #ffffff;
    --nav-bg: rgba(251,250,238,0.82);
    --shadow: rgba(20,20,20,0.14);
    --shadow-strong: rgba(20,20,20,0.24);
    --panel: #171717;
    --panel-2: #222222;
    --panel-line: rgba(255,255,255,0.14);
    --panel-text: rgba(255,255,255,0.72);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      color-scheme: dark;
      --bg: #08090b;
      --bg-2: #111318;
      --surface: #12141a;
      --surface-soft: #191c22;
      --ink: #fbfaf4;
      --ink-soft: #d3d2ca;
      --muted: #96958c;
      --line: rgba(255,255,255,0.13);
      --line-strong: rgba(255,255,255,0.24);
      --accent: #ff5a52;
      --accent-strong: #ff7a73;
      --accent-soft: rgba(255,90,82,0.16);
      --lavender: rgba(210,160,255,0.18);
      --sage: rgba(120,230,140,0.16);
      --blue: rgba(120,170,255,0.18);
      --button-text: #ffffff;
      --nav-bg: rgba(8,9,11,0.78);
      --shadow: rgba(0,0,0,0.46);
      --shadow-strong: rgba(0,0,0,0.62);
      --panel: #171717;
      --panel-2: #222222;
      --panel-line: rgba(255,255,255,0.14);
      --panel-text: rgba(255,255,255,0.72);
    }
  }
  :root[data-theme="dark"] {
    color-scheme: dark;
    --bg: #08090b;
    --bg-2: #111318;
    --surface: #12141a;
    --surface-soft: #191c22;
    --ink: #fbfaf4;
    --ink-soft: #d3d2ca;
    --muted: #96958c;
    --line: rgba(255,255,255,0.13);
    --line-strong: rgba(255,255,255,0.24);
    --accent: #ff5a52;
    --accent-strong: #ff7a73;
    --accent-soft: rgba(255,90,82,0.16);
    --lavender: rgba(210,160,255,0.18);
    --sage: rgba(120,230,140,0.16);
    --blue: rgba(120,170,255,0.18);
    --button-text: #ffffff;
    --nav-bg: rgba(8,9,11,0.78);
    --shadow: rgba(0,0,0,0.46);
    --shadow-strong: rgba(0,0,0,0.62);
    --panel: #171717;
    --panel-2: #222222;
    --panel-line: rgba(255,255,255,0.14);
    --panel-text: rgba(255,255,255,0.72);
  }
  :root[data-theme="light"] {
    color-scheme: light;
    --bg: #fbfaee;
    --bg-2: #f1f0e2;
    --surface: #fffff8;
    --surface-soft: #f6f5e8;
    --ink: #141414;
    --ink-soft: #3f403d;
    --muted: #707066;
    --line: rgba(20,20,20,0.14);
    --line-strong: rgba(20,20,20,0.24);
    --accent: #ff473f;
    --accent-strong: #d9302a;
    --accent-soft: #ffe0dc;
    --lavender: #ecd7ff;
    --sage: #dff4dc;
    --blue: #dbeaff;
    --button-text: #ffffff;
    --nav-bg: rgba(251,250,238,0.82);
    --shadow: rgba(20,20,20,0.14);
    --shadow-strong: rgba(20,20,20,0.24);
    --panel: #171717;
    --panel-2: #222222;
    --panel-line: rgba(255,255,255,0.14);
    --panel-text: rgba(255,255,255,0.72);
  }
  * { box-sizing: border-box; }
  html { scroll-behavior: smooth; }
  body {
    margin: 0;
    min-height: 100vh;
    background: var(--bg);
    color: var(--ink);
    font: 16px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  a { color: inherit; text-decoration: none; }
  ::selection { background: var(--accent); color: #fff; }
  .wrap { width: min(1120px, calc(100% - 40px)); margin: 0 auto; }
  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }
  nav {
    position: sticky;
    top: 0;
    z-index: 30;
    border-bottom: 1px solid var(--line);
    background: var(--nav-bg);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
  }
  .nav-inner {
    height: 68px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 18px;
  }
  .brand {
    min-width: max-content;
    display: inline-flex;
    align-items: center;
    gap: 10px;
    font-weight: 760;
  }
  .brand img {
    width: 28px;
    height: 28px;
    border-radius: 7px;
    box-shadow: 0 12px 22px rgba(255,71,63,0.24);
  }
  .nav-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .icon-button {
    width: 40px;
    padding: 0;
  }
  .button, .icon-button {
    min-height: 40px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    border-radius: 8px;
    border: 1px solid var(--line);
    background: var(--surface);
    color: var(--ink);
    font: inherit;
    font-size: 14px;
    font-weight: 720;
    padding: 9px 14px;
    cursor: pointer;
  }
  .icon-button {
    padding: 0;
    border-color: transparent;
    background: transparent;
  }
  .button:hover { border-color: var(--line-strong); }
  .icon-button:hover {
    border-color: transparent;
    background: var(--surface-soft);
  }
  .button.primary {
    background: var(--accent);
    border-color: transparent;
    color: var(--button-text);
    box-shadow: 0 16px 34px -20px rgba(255,71,63,0.8);
  }
  .button.primary:hover {
    background: var(--accent-strong);
  }
  .theme-icon {
    width: 19px;
    height: 19px;
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;
  }
  .theme-icon.sun-icon {
    display: none;
  }
  :root[data-theme="dark"] .theme-icon.moon-icon {
    display: none;
  }
  :root[data-theme="dark"] .theme-icon.sun-icon {
    display: block;
  }
  .github-mark {
    width: 18px;
    height: 18px;
    fill: currentColor;
  }
  .hero {
    position: relative;
    padding: 68px 0 68px;
    overflow: hidden;
  }
  .hero::before {
    content: "";
    position: absolute;
    inset: 0;
    background:
      linear-gradient(var(--line) 1px, transparent 1px),
      linear-gradient(90deg, var(--line) 1px, transparent 1px);
    background-size: 56px 56px;
    mask-image: linear-gradient(to bottom, rgba(0,0,0,0.32), transparent 68%);
    pointer-events: none;
  }
  .hero-grid {
    position: relative;
    z-index: 1;
    display: grid;
    grid-template-columns: minmax(0, 0.95fr) minmax(360px, 1.05fr);
    gap: 52px;
    align-items: center;
  }
  .hero-copy-block {
    max-width: 590px;
  }
  .eyebrow {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 18px;
    color: var(--accent-strong);
    font-size: 12px;
    font-weight: 820;
    text-transform: uppercase;
  }
  .eyebrow::before {
    content: "";
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--accent);
    box-shadow: 0 0 18px rgba(255,71,63,0.72);
  }
  h1 {
    margin: 0 0 20px;
    font: 820 62px/0.98 -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", Roboto, sans-serif;
  }
  .hero-copy {
    max-width: 560px;
    margin: 0;
    color: var(--ink-soft);
    font-size: 20px;
  }
  .cta-row {
    margin-top: 30px;
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
  }
  .fine-print {
    margin: 14px 0 0;
    color: var(--muted);
    font-size: 13px;
  }

  .demo-stage {
    position: relative;
    min-height: 430px;
  }
  .recorder-card {
    position: absolute;
    right: 0;
    top: 0;
    width: min(100%, 460px);
    border: 1px solid var(--line-strong);
    border-radius: 8px;
    background: var(--surface);
    box-shadow: 0 34px 90px -54px var(--shadow-strong);
    overflow: hidden;
    animation: floatCard 7s ease-in-out infinite;
  }
  .card-top {
    height: 42px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 14px;
    border-bottom: 1px solid var(--line);
    background: var(--surface-soft);
  }
  .traffic { width: 11px; height: 11px; border-radius: 50%; background: #ff5f57; }
  .traffic:nth-child(2) { background: #febc2e; }
  .traffic:nth-child(3) { background: #28c840; }
  .card-title {
    margin-left: 8px;
    color: var(--muted);
    font-size: 12px;
    font-weight: 720;
  }
  .card-body { padding: 22px; }
  .menu-head {
    display: flex;
    align-items: center;
    gap: 12px;
    padding-bottom: 18px;
    border-bottom: 1px solid var(--line);
  }
  .menu-head img { width: 34px; height: 34px; border-radius: 8px; }
  .menu-title { font-weight: 780; }
  .menu-sub { color: var(--muted); font-size: 13px; }
  .settings {
    display: grid;
    gap: 10px;
    padding: 18px 0;
    border-bottom: 1px solid var(--line);
  }
  .setting {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    color: var(--muted);
    font-size: 14px;
  }
  .setting strong { color: var(--ink); }
  .record-button {
    margin-top: 18px;
    min-height: 46px;
    border-radius: 8px;
    background: var(--accent);
    color: #fff;
    display: grid;
    place-items: center;
    font-weight: 820;
  }
  .share-row {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 18px;
    color: var(--muted);
    font-size: 13px;
  }
  .share-dot {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: var(--accent);
  }
  .share-link {
    margin-left: auto;
    color: #1f9d5a;
    font-weight: 820;
  }
  .proof-band {
    position: relative;
    z-index: 2;
    background: var(--panel);
    color: #fff;
    padding: 78px 0;
  }
  .proof-layout {
    display: grid;
    grid-template-columns: minmax(0, 0.82fr) minmax(0, 1.18fr);
    gap: 52px;
    align-items: start;
  }
  .proof-copy {
    position: sticky;
    top: 104px;
  }
  .proof-kicker {
    margin: 0 0 12px;
    color: var(--accent-strong);
    font-size: 12px;
    font-weight: 820;
    text-transform: uppercase;
  }
  h2 {
    margin: 0;
    font: 820 44px/1.05 -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", Roboto, sans-serif;
  }
  .proof-copy p:last-child {
    margin: 18px 0 0;
    color: var(--panel-text);
    font-size: 18px;
  }
  .proof-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
  }
  .proof-item {
    min-height: 172px;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    padding: 22px;
    border: 1px solid var(--panel-line);
    border-radius: 8px;
    background: rgba(255,255,255,0.045);
  }
  .proof-item:nth-child(1) { background: rgba(255,71,63,0.13); }
  .proof-item p {
    margin: 16px 0 0;
    color: var(--panel-text);
    font-size: 15px;
    line-height: 1.5;
  }
  .proof-item span {
    display: block;
    color: #fff;
    font-size: 25px;
    line-height: 1.08;
    font-weight: 820;
  }

  footer {
    border-top: 1px solid var(--line);
    padding: 24px 0;
    color: var(--muted);
    font-size: 13px;
  }
  .foot {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 14px;
    flex-wrap: wrap;
  }
  footer a { color: var(--ink-soft); }
  footer a:hover { color: var(--ink); text-decoration: underline; }

  @keyframes floatCard {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-10px); }
  }
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
      animation-duration: 0.001ms !important;
      animation-iteration-count: 1 !important;
      scroll-behavior: auto !important;
    }
  }
  @media (max-width: 980px) {
    .hero { min-height: 0; padding-top: 56px; }
    .hero-grid {
      grid-template-columns: 1fr;
      gap: 34px;
    }
    h1 { font-size: 58px; }
    .demo-stage { min-height: 430px; }
    .recorder-card { left: 0; right: auto; }
    .proof-layout {
      grid-template-columns: 1fr;
      gap: 32px;
    }
    .proof-copy { position: static; }
  }
  @media (max-width: 720px) {
    .wrap { width: min(1120px, calc(100% - 28px)); }
    html, body { overflow-x: hidden; }
    .nav-inner { height: 64px; position: relative; gap: 10px; }
    .nav-actions { gap: 6px; }
    .icon-button { width: 38px; min-height: 38px; }
    .nav-actions .button.primary { min-height: 38px; padding: 8px 11px; }
    .hero { padding-top: 48px; }
    h1 { font-size: 46px; }
    h2 { font-size: 34px; }
    .hero-copy { font-size: 18px; }
    .cta-row { display: grid; grid-template-columns: 1fr; }
    .button { min-width: 0; }
    .cta-row .button { justify-content: center; }
    .demo-stage { min-height: 370px; overflow: hidden; }
    .recorder-card {
      top: 18px;
      width: 100%;
    }
    .setting { align-items: flex-start; }
    .setting strong {
      min-width: 0;
      max-width: 56%;
      text-align: right;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .share-row span:nth-child(2) {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .card-body { padding: 18px; }
    .proof-band { padding: 54px 0; }
    .proof-grid { grid-template-columns: 1fr; }
    .proof-item { min-height: 138px; padding: 18px; }
    .proof-item span { font-size: 22px; }
  }
  @media (max-width: 420px) {
    .brand span { display: none; }
  }
</style>
</head>
<body>

<nav>
  <div class="wrap nav-inner">
    <a class="brand" href="/">
      <img src="/assets/icon.png" alt="">
      <span>${BRAND}</span>
    </a>
    <div class="nav-actions">
      <button class="icon-button theme-toggle" type="button" data-theme-toggle>
        <svg class="theme-icon moon-icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M21 12.8A8.7 8.7 0 1 1 11.2 3 6.8 6.8 0 0 0 21 12.8Z"></path>
        </svg>
        <svg class="theme-icon sun-icon" viewBox="0 0 24 24" aria-hidden="true">
          <circle cx="12" cy="12" r="4"></circle>
          <path d="M12 2v2"></path>
          <path d="M12 20v2"></path>
          <path d="m4.9 4.9 1.4 1.4"></path>
          <path d="m17.7 17.7 1.4 1.4"></path>
          <path d="M2 12h2"></path>
          <path d="M20 12h2"></path>
          <path d="m4.9 19.1 1.4-1.4"></path>
          <path d="m17.7 6.3 1.4-1.4"></path>
        </svg>
        <span class="sr-only" data-theme-label>Theme</span>
      </button>
      <a class="icon-button" href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer" aria-label="GitHub">
        <svg class="github-mark" viewBox="0 0 16 16" aria-hidden="true">
          <path d="M8 0C3.58 0 0 3.67 0 8.19c0 3.62 2.29 6.69 5.47 7.77.4.08.55-.18.55-.39 0-.19-.01-.84-.01-1.53-2.01.38-2.53-.5-2.69-.96-.09-.23-.48-.96-.82-1.16-.28-.16-.68-.55-.01-.56.63-.01 1.08.59 1.23.83.72 1.24 1.87.89 2.33.68.07-.53.28-.89.51-1.09-1.78-.21-3.64-.91-3.64-4.03 0-.89.31-1.62.82-2.2-.08-.21-.36-1.04.08-2.17 0 0 .67-.22 2.2.84A7.38 7.38 0 0 1 8 3.95c.68 0 1.36.09 2 .27 1.53-1.06 2.2-.84 2.2-.84.44 1.13.16 1.96.08 2.17.51.58.82 1.31.82 2.2 0 3.13-1.87 3.82-3.65 4.03.29.26.54.75.54 1.52 0 1.09-.01 1.97-.01 2.24 0 .21.15.47.55.39A8.13 8.13 0 0 0 16 8.19C16 3.67 12.42 0 8 0Z"/>
        </svg>
      </a>
      <a class="button primary" href="${DOWNLOAD_URL}" download>Download</a>
    </div>
  </div>
</nav>

<main>
  <section class="hero">
    <div class="wrap hero-grid">
      <div class="hero-copy-block">
        <div class="eyebrow">Open source &middot; local first &middot; no account &middot; Mac screen recorder</div>
        <h1>Record locally. Share only if needed.</h1>
        <p class="hero-copy">An open-source Mac recorder for demos and bug reports. Files stay on your Mac unless you choose to upload a temporary link.</p>
        <div class="cta-row">
          <a class="button primary" href="${DOWNLOAD_URL}" download>Download for Mac</a>
        </div>
        <p class="fine-print">macOS 15+ &middot; Apple Silicon and Intel &middot; Apache-2.0</p>
      </div>

      <div class="demo-stage" aria-label="Screencast.to recording workflow preview">
        <div class="recorder-card">
          <div class="card-top">
            <span class="traffic"></span><span class="traffic"></span><span class="traffic"></span>
            <span class="card-title">Screencast.to</span>
          </div>
          <div class="card-body">
            <div class="menu-head">
              <img src="/assets/icon.png" alt="">
              <div>
                <div class="menu-title">Ready to record</div>
                <div class="menu-sub">Stored on this Mac</div>
              </div>
            </div>
            <div class="settings">
              <div class="setting"><span>Capture</span><strong>Screen + Camera</strong></div>
              <div class="setting"><span>Audio</span><strong>Mic + System</strong></div>
              <div class="setting"><span>Sharing</span><strong>Only when uploaded</strong></div>
            </div>
            <div class="record-button">Start Recording</div>
            <div class="share-row">
              <span class="share-dot"></span>
              <span>Screencast 2.0.1.mov</span>
              <span class="share-link">Upload</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <section class="proof-band" aria-label="Product principles">
    <div class="wrap proof-layout">
      <div class="proof-copy">
        <p class="proof-kicker">Why Screencast.to</p>
        <h2>Screen recording without the black box.</h2>
        <p>Capture from the menu bar, keep the file locally, and create a browser link only when sharing actually helps.</p>
      </div>
      <div class="proof-grid">
        <div class="proof-item"><span>Local first</span><p>Recordings are files on your Mac before anything leaves the machine.</p></div>
        <div class="proof-item"><span>Open source</span><p>The macOS app and Cloudflare worker are public, inspectable, and Apache-2.0 licensed.</p></div>
        <div class="proof-item"><span>Optional links</span><p>Upload only when needed. Shared videos are short-lived instead of becoming a permanent library.</p></div>
        <div class="proof-item"><span>No account wall</span><p>Viewers can open the link in a browser without signing in or joining a workspace.</p></div>
      </div>
    </div>
  </section>
</main>

<footer>
  <div class="wrap foot">
    <span>&copy; ${new Date().getFullYear()} ${BRAND}</span>
    <span>Local first &middot; Open source &middot; Optional sharing &middot; <a href="/privacy">Privacy</a> &middot; <a href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">GitHub</a></span>
  </div>
</footer>

</body>
</html>`;
}
