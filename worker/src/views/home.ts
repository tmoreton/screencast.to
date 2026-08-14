import { BRAND, DOWNLOAD_URL, FAVICON_HREF, GA_SNIPPET, GITHUB_URL, OG_IMAGE_URL, THEME_SCRIPT } from "./shared";

/** Landing page at GET /. */
export function renderHome(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#f7f4ef" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0c0d0f" media="(prefers-color-scheme: dark)">
<title>${BRAND} - Temporary screen recording for Mac</title>
<meta name="description" content="Screencast.to is a tiny open-source macOS menu-bar recorder. Record locally, then share an optional 24-hour link. No accounts, no permanent video library.">
<meta name="keywords" content="screen recorder, mac screen recording, loom alternative, free screen recorder, open source screen recorder, macOS, temporary video link">
<meta name="author" content="Screencast.to">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://screencast.to/">
<link rel="icon" href="${FAVICON_HREF}">

<meta property="og:site_name" content="Screencast.to">
<meta property="og:title" content="Screencast.to - Temporary screen recording for Mac">
<meta property="og:description" content="Record locally. Share a 24-hour link only when you choose. Open source, no accounts.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://screencast.to/">
<meta property="og:image" content="${OG_IMAGE_URL}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Screencast.to landing page">
<meta property="og:locale" content="en_US">

<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Screencast.to - Temporary screen recording for Mac">
<meta name="twitter:description" content="A tiny open-source Mac recorder for local captures and optional 24-hour share links.">
<meta name="twitter:image" content="${OG_IMAGE_URL}">

${GA_SNIPPET}
${THEME_SCRIPT}
<style>
  :root {
    color-scheme: light;
    --bg: #f7f4ef;
    --surface: #fffaf4;
    --surface-2: #efe7dc;
    --surface-3: #e4dccf;
    --line: #d4cabd;
    --line-strong: #b9aa99;
    --text: #191613;
    --text-soft: #4e463e;
    --muted: #756b61;
    --accent: #e9363f;
    --accent-strong: #c91f2b;
    --accent-soft: #ffe0df;
    --good: #26734d;
    --button-text: #ffffff;
    --shadow: rgba(75, 51, 35, 0.16);
    --nav-bg: rgba(247, 244, 239, 0.84);
    --mock-screen: #24282f;
    --mock-screen-2: #303641;
    --mock-line: rgba(255,255,255,0.14);
    --mock-text: rgba(255,255,255,0.72);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      color-scheme: dark;
      --bg: #0c0d0f;
      --surface: #15171b;
      --surface-2: #1d2026;
      --surface-3: #282c34;
      --line: #2b3038;
      --line-strong: #3c424d;
      --text: #f4f1ec;
      --text-soft: #d0c8bd;
      --muted: #9b9389;
      --accent: #ff4b55;
      --accent-strong: #ff6870;
      --accent-soft: rgba(255,75,85,0.14);
      --good: #6fe09f;
      --button-text: #ffffff;
      --shadow: rgba(0,0,0,0.46);
      --nav-bg: rgba(12, 13, 15, 0.78);
      --mock-screen: #222731;
      --mock-screen-2: #111318;
      --mock-line: rgba(255,255,255,0.12);
      --mock-text: rgba(255,255,255,0.76);
    }
  }
  :root[data-theme="dark"] {
    color-scheme: dark;
    --bg: #0c0d0f;
    --surface: #15171b;
    --surface-2: #1d2026;
    --surface-3: #282c34;
    --line: #2b3038;
    --line-strong: #3c424d;
    --text: #f4f1ec;
    --text-soft: #d0c8bd;
    --muted: #9b9389;
    --accent: #ff4b55;
    --accent-strong: #ff6870;
    --accent-soft: rgba(255,75,85,0.14);
    --good: #6fe09f;
    --button-text: #ffffff;
    --shadow: rgba(0,0,0,0.46);
    --nav-bg: rgba(12, 13, 15, 0.78);
    --mock-screen: #222731;
    --mock-screen-2: #111318;
    --mock-line: rgba(255,255,255,0.12);
    --mock-text: rgba(255,255,255,0.76);
  }
  :root[data-theme="light"] {
    color-scheme: light;
    --bg: #f7f4ef;
    --surface: #fffaf4;
    --surface-2: #efe7dc;
    --surface-3: #e4dccf;
    --line: #d4cabd;
    --line-strong: #b9aa99;
    --text: #191613;
    --text-soft: #4e463e;
    --muted: #756b61;
    --accent: #e9363f;
    --accent-strong: #c91f2b;
    --accent-soft: #ffe0df;
    --good: #26734d;
    --button-text: #ffffff;
    --shadow: rgba(75, 51, 35, 0.16);
    --nav-bg: rgba(247, 244, 239, 0.84);
    --mock-screen: #24282f;
    --mock-screen-2: #303641;
    --mock-line: rgba(255,255,255,0.14);
    --mock-text: rgba(255,255,255,0.72);
  }
  * { box-sizing: border-box; }
  html { scroll-behavior: smooth; }
  body {
    margin: 0;
    min-height: 100vh;
    background: var(--bg);
    color: var(--text);
    font: 16px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  a { color: inherit; text-decoration: none; }
  ::selection { background: var(--accent); color: #fff; }
  .wrap { width: min(1120px, calc(100% - 40px)); margin: 0 auto; }
  nav {
    position: sticky;
    top: 0;
    z-index: 20;
    background: var(--nav-bg);
    border-bottom: 1px solid var(--line);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
  }
  .nav-inner {
    height: 72px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 18px;
  }
  .brand {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    font-weight: 700;
  }
  .brand img {
    width: 28px;
    height: 28px;
    border-radius: 7px;
    box-shadow: 0 8px 18px rgba(233,54,63,0.24);
  }
  .nav-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .nav-link {
    color: var(--text-soft);
    font-size: 14px;
    padding: 8px 10px;
  }
  .nav-link:hover { color: var(--text); }
  .button, .theme-toggle {
    min-height: 40px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    border-radius: 8px;
    border: 1px solid var(--line);
    background: var(--surface);
    color: var(--text);
    font: inherit;
    font-size: 14px;
    font-weight: 700;
    padding: 9px 13px;
    cursor: pointer;
  }
  .button:hover, .theme-toggle:hover { border-color: var(--line-strong); }
  .button.primary {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--button-text);
    box-shadow: 0 14px 28px -18px var(--accent);
  }
  .button.primary:hover {
    background: var(--accent-strong);
    border-color: var(--accent-strong);
  }
  .theme-toggle::before {
    content: "";
    width: 15px;
    height: 15px;
    border-radius: 50%;
    background: linear-gradient(90deg, var(--accent) 0 50%, var(--surface-3) 50% 100%);
    border: 1px solid var(--line-strong);
  }

  .hero {
    padding: 78px 0 54px;
    text-align: center;
  }
  .eyebrow {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 18px;
    color: var(--accent);
    background: var(--accent-soft);
    border: 1px solid color-mix(in srgb, var(--accent) 24%, transparent);
    border-radius: 999px;
    padding: 7px 12px;
    font-size: 12px;
    font-weight: 800;
    text-transform: uppercase;
  }
  .eyebrow::before {
    content: "";
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--accent);
  }
  h1 {
    margin: 0 auto 18px;
    max-width: 820px;
    font-size: 64px;
    line-height: 1.02;
    font-weight: 800;
  }
  .hero-copy {
    max-width: 680px;
    margin: 0 auto;
    color: var(--text-soft);
    font-size: 19px;
  }
  .cta-row {
    margin-top: 28px;
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 10px;
  }
  .fine-print {
    margin: 14px 0 0;
    color: var(--muted);
    font-size: 13px;
  }
  .facts {
    margin: 28px auto 0;
    padding: 0;
    display: flex;
    justify-content: center;
    gap: 10px;
    flex-wrap: wrap;
    list-style: none;
  }
  .facts li {
    border: 1px solid var(--line);
    background: var(--surface);
    border-radius: 999px;
    padding: 7px 11px;
    color: var(--text-soft);
    font-size: 13px;
    font-weight: 650;
  }

  .product {
    margin: 44px auto 0;
    max-width: 920px;
    text-align: left;
    border: 1px solid var(--line-strong);
    border-radius: 8px;
    background: var(--mock-screen);
    box-shadow: 0 32px 80px -44px var(--shadow), 0 1px 0 rgba(255,255,255,0.08) inset;
    overflow: hidden;
  }
  .product-top {
    height: 42px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 14px;
    border-bottom: 1px solid var(--mock-line);
    background: var(--mock-screen-2);
  }
  .traffic { width: 11px; height: 11px; border-radius: 50%; background: #ff5f57; }
  .traffic:nth-child(2) { background: #febc2e; }
  .traffic:nth-child(3) { background: #28c840; }
  .product-body {
    position: relative;
    min-height: 430px;
    padding: 28px;
    color: #f6f3ef;
    display: grid;
    grid-template-columns: 300px 1fr;
    gap: 22px;
  }
  .menu-panel {
    align-self: start;
    border: 1px solid var(--mock-line);
    border-radius: 8px;
    background: rgba(255,255,255,0.08);
    box-shadow: 0 18px 50px rgba(0,0,0,0.22);
    overflow: hidden;
  }
  .menu-head, .menu-row, .recording-row {
    display: flex;
    align-items: center;
    gap: 10px;
    border-bottom: 1px solid var(--mock-line);
    padding: 13px 14px;
  }
  .menu-head img { width: 24px; height: 24px; border-radius: 6px; }
  .menu-title { font-weight: 750; }
  .menu-sub { color: var(--mock-text); font-size: 12px; }
  .menu-row { justify-content: space-between; color: var(--mock-text); font-size: 13px; }
  .menu-row strong { color: #fff; font-weight: 700; }
  .start-button {
    margin: 14px;
    height: 42px;
    border-radius: 8px;
    background: var(--accent);
    display: grid;
    place-items: center;
    color: #fff;
    font-weight: 800;
  }
  .recording-row { border-bottom: 0; align-items: flex-start; }
  .recording-dot { width: 9px; height: 9px; margin-top: 6px; border-radius: 50%; background: var(--accent); }
  .upload { margin-left: auto; color: var(--good); font-weight: 800; font-size: 12px; }
  .screen {
    min-height: 330px;
    border: 1px solid var(--mock-line);
    border-radius: 8px;
    background:
      linear-gradient(180deg, rgba(255,255,255,0.07), rgba(255,255,255,0.02)),
      var(--mock-screen-2);
    padding: 20px;
  }
  .screen-toolbar {
    display: flex;
    gap: 10px;
    align-items: center;
    margin-bottom: 22px;
  }
  .avatar { width: 28px; height: 28px; border-radius: 50%; background: #7b8494; }
  .line { height: 10px; border-radius: 999px; background: rgba(255,255,255,0.16); }
  .line.a { width: 44%; }
  .line.b { width: 20%; margin-left: auto; }
  .screen-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 12px;
    margin-bottom: 16px;
  }
  .screen-card {
    height: 90px;
    border-radius: 8px;
    border: 1px solid var(--mock-line);
    background: rgba(255,255,255,0.06);
    padding: 14px;
  }
  .screen-card .line { margin-bottom: 14px; }
  .screen-card .line:last-child { width: 62%; background: rgba(111,224,159,0.5); }
  .bars {
    height: 142px;
    border: 1px solid var(--mock-line);
    border-radius: 8px;
    background: rgba(0,0,0,0.12);
    display: flex;
    align-items: end;
    gap: 8px;
    padding: 14px;
  }
  .bars span {
    flex: 1;
    min-width: 8px;
    border-radius: 4px 4px 0 0;
    background: rgba(255,255,255,0.18);
  }
  .bars span:nth-child(4), .bars span:nth-child(5), .bars span:nth-child(7) {
    background: rgba(255,75,85,0.6);
  }
  .countdown {
    position: absolute;
    top: 70px;
    left: 50%;
    transform: translateX(-50%);
    min-width: 246px;
    height: 46px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    border-radius: 999px;
    border: 1px solid rgba(255,255,255,0.18);
    background: rgba(12,13,15,0.8);
    box-shadow: 0 18px 40px rgba(0,0,0,0.28);
    backdrop-filter: blur(14px);
    color: #fff;
    font-weight: 800;
  }
  .countdown .pulse {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: #f6a23a;
    box-shadow: 0 0 16px rgba(246,162,58,0.78);
  }
  .camera {
    position: absolute;
    right: 48px;
    bottom: 42px;
    width: 106px;
    height: 106px;
    border-radius: 50%;
    border: 4px solid rgba(255,255,255,0.88);
    background: linear-gradient(145deg, #b4bfcb, #5b6471);
    display: grid;
    place-items: center;
    color: rgba(255,255,255,0.72);
    font-weight: 900;
    box-shadow: 0 18px 38px rgba(0,0,0,0.36);
  }
  .camera::before {
    content: "";
    width: 44px;
    height: 44px;
    border-radius: 50%;
    background: rgba(255,255,255,0.28);
    box-shadow: 0 40px 0 18px rgba(255,255,255,0.18);
  }

  section {
    padding: 70px 0;
    border-top: 1px solid var(--line);
  }
  .section-head {
    max-width: 620px;
    margin-bottom: 28px;
  }
  h2 {
    margin: 0 0 10px;
    font-size: 34px;
    line-height: 1.16;
  }
  .section-head p, .split p, .card p, .step p {
    color: var(--text-soft);
    margin: 0;
  }
  .cards {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 14px;
  }
  .card {
    min-height: 170px;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 8px;
    padding: 22px;
  }
  .card small {
    display: inline-block;
    color: var(--accent);
    font-weight: 850;
    text-transform: uppercase;
    font-size: 11px;
    margin-bottom: 14px;
  }
  .card h3 {
    margin: 0 0 8px;
    font-size: 18px;
  }
  .steps {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 18px;
  }
  .step {
    border-left: 3px solid var(--accent);
    padding-left: 18px;
  }
  .step strong {
    display: block;
    margin-bottom: 6px;
    font-size: 18px;
  }
  .split {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 28px;
    align-items: start;
  }
  .checks {
    list-style: none;
    padding: 0;
    margin: 0;
    display: grid;
    gap: 10px;
  }
  .checks li {
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--surface);
    padding: 14px 16px;
    color: var(--text-soft);
  }
  .checks strong { color: var(--text); }
  .final-cta {
    text-align: center;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 8px;
    padding: 42px 24px;
  }
  .final-cta h2 { margin-bottom: 12px; }
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
  footer a { color: var(--text-soft); }
  footer a:hover { color: var(--text); text-decoration: underline; }

  @media (max-width: 840px) {
    .nav-inner { height: auto; padding: 14px 0; align-items: flex-start; }
    .nav-actions { flex-wrap: wrap; justify-content: flex-end; }
    .nav-link { display: none; }
    h1 { font-size: 46px; }
    .hero { padding-top: 54px; }
    .product-body { grid-template-columns: 1fr; min-height: 0; }
    .countdown { top: 360px; }
    .cards, .steps, .split { grid-template-columns: 1fr; }
    .screen-grid { grid-template-columns: 1fr; }
  }
  @media (max-width: 560px) {
    .wrap { width: min(1120px, calc(100% - 28px)); }
    h1 { font-size: 38px; }
    h2 { font-size: 28px; }
    .hero { text-align: left; }
    .hero-copy { font-size: 17px; max-width: 360px; margin-left: 0; margin-right: 0; }
    .cta-row, .facts { justify-content: flex-start; max-width: 360px; }
    .button, .theme-toggle { width: 100%; }
    .nav-actions { width: 100%; flex-direction: column; align-items: stretch; }
    .brand { margin-bottom: 4px; }
    .nav-inner { display: block; }
    .product-body { padding: 16px; }
    .screen { display: none; }
    .countdown { position: static; transform: none; margin: 16px 0 0; width: 100%; }
    .camera { display: none; }
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
      <a class="nav-link" href="#what">What it does</a>
      <a class="nav-link" href="/privacy">Privacy</a>
      <button class="theme-toggle" type="button" data-theme-toggle><span data-theme-label>Theme</span></button>
      <a class="button" href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">GitHub</a>
      <a class="button primary" href="${DOWNLOAD_URL}" download>Download</a>
    </div>
  </div>
</nav>

<main>
  <section class="hero wrap">
    <div class="eyebrow">Open-source macOS recorder</div>
    <h1>Temporary screen recording for Mac</h1>
    <p class="hero-copy">${BRAND} records locally from your menu bar. When you need to share, it uploads one file and gives you a 24-hour link. No accounts. No permanent cloud library.</p>
    <div class="cta-row">
      <a class="button primary" href="${DOWNLOAD_URL}" download>Download for Mac</a>
      <a class="button" href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">View source</a>
    </div>
    <p class="fine-print">macOS 15+ · Apple Silicon and Intel · Apache-2.0</p>
    <ul class="facts">
      <li>Screen, camera, mic, system audio</li>
      <li>Camera countdown before recording</li>
      <li>Viewer links expire after 24 hours</li>
      <li>Viewers never need an account</li>
    </ul>

    <div class="product" aria-label="Screencast.to recording workflow preview">
      <div class="product-top"><span class="traffic"></span><span class="traffic"></span><span class="traffic"></span></div>
      <div class="product-body">
        <div class="menu-panel">
          <div class="menu-head">
            <img src="/assets/icon.png" alt="">
            <div>
              <div class="menu-title">Ready to record</div>
              <div class="menu-sub">Local by default</div>
            </div>
          </div>
          <div class="menu-row"><span>Format</span><strong>Screen + Camera</strong></div>
          <div class="menu-row"><span>Microphone</span><strong>System default</strong></div>
          <div class="menu-row"><span>Share link</span><strong>24 hours</strong></div>
          <div class="start-button">Start Recording</div>
          <div class="recording-row">
            <span class="recording-dot"></span>
            <div>
              <div class="menu-title">Screencast 2.0.1.mov</div>
              <div class="menu-sub">Stored on this Mac</div>
            </div>
            <span class="upload">Upload</span>
          </div>
        </div>
        <div class="screen">
          <div class="screen-toolbar">
            <div class="avatar"></div>
            <div class="line a"></div>
            <div class="line b"></div>
          </div>
          <div class="screen-grid">
            <div class="screen-card"><div class="line"></div><div class="line"></div></div>
            <div class="screen-card"><div class="line"></div><div class="line"></div></div>
            <div class="screen-card"><div class="line"></div><div class="line"></div></div>
          </div>
          <div class="bars">
            <span style="height:36%"></span><span style="height:52%"></span><span style="height:42%"></span><span style="height:78%"></span><span style="height:66%"></span><span style="height:46%"></span><span style="height:88%"></span><span style="height:58%"></span>
          </div>
        </div>
        <div class="countdown"><span class="pulse"></span><span>00:03 · camera warming up</span></div>
        <div class="camera"></div>
      </div>
    </div>
  </section>

  <section id="what">
    <div class="wrap">
      <div class="section-head">
        <h2>What it does</h2>
        <p>A short list, because the app should be obvious.</p>
      </div>
      <div class="cards">
        <article class="card">
          <small>Record</small>
          <h3>Capture the screen you actually need.</h3>
          <p>Full display or selected region, with cursor, camera bubble, microphone, and system audio.</p>
        </article>
        <article class="card">
          <small>Keep</small>
          <h3>Your recording starts on your Mac.</h3>
          <p>Files are local first. Upload happens only when you click the upload control.</p>
        </article>
        <article class="card">
          <small>Share</small>
          <h3>Send a link that expires.</h3>
          <p>The viewer opens in a browser and disappears after 24 hours. No viewer login.</p>
        </article>
      </div>
    </div>
  </section>

  <section>
    <div class="wrap">
      <div class="section-head">
        <h2>How it works</h2>
        <p>The normal workflow is three clicks.</p>
      </div>
      <div class="steps">
        <div class="step">
          <strong>1. Pick your capture.</strong>
          <p>Choose screen, camera layout, microphone, and optional region from the menu bar.</p>
        </div>
        <div class="step">
          <strong>2. Record after the countdown.</strong>
          <p>Camera formats wait a few seconds so the camera can wake up before frames are written.</p>
        </div>
        <div class="step">
          <strong>3. Upload only if needed.</strong>
          <p>Copy a 24-hour link, or keep the file local and share it another way.</p>
        </div>
      </div>
    </div>
  </section>

  <section>
    <div class="wrap split">
      <div>
        <h2>Small by design</h2>
        <p>${BRAND} is for quick work recordings: bug reports, walkthroughs, demos, and async updates. It is not a workspace, not a social feed, and not a place where videos pile up forever.</p>
      </div>
      <ul class="checks">
        <li><strong>Open source:</strong> Swift app, Cloudflare Worker, and static site are public.</li>
        <li><strong>Temporary uploads:</strong> shared recordings auto-delete after 24 hours.</li>
        <li><strong>No accounts:</strong> no sign-up for you or your viewer.</li>
      </ul>
    </div>
  </section>

  <section>
    <div class="wrap final-cta">
      <h2>Get ${BRAND}</h2>
      <p class="hero-copy">Free, open source, and built for macOS 15 or newer.</p>
      <div class="cta-row">
        <a class="button primary" href="${DOWNLOAD_URL}" download>Download .dmg</a>
        <a class="button" href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">Read the code</a>
      </div>
    </div>
  </section>
</main>

<footer>
  <div class="wrap foot">
    <span>&copy; ${new Date().getFullYear()} ${BRAND}</span>
    <span>Local first · 24-hour links · <a href="/privacy">Privacy</a> · <a href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">GitHub</a></span>
  </div>
</footer>

</body>
</html>`;
}
