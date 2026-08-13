import { BRAND, DOWNLOAD_URL, FAVICON_HREF, GA_SNIPPET, OG_IMAGE_URL } from "./shared";

/** Landing page at GET /. */
export function renderHome(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#0a0c10">
<title>${BRAND} — Temporary screen recordings for work</title>
<meta name="description" content="A tiny macOS menu-bar app. Record locally, then share a 24-hour link when you choose. No accounts, no viewer login, no permanent video library.">
<meta name="keywords" content="screen recorder, mac screen recording, loom alternative, free screen recorder, macOS, share screen recording, screencast">
<meta name="author" content="Screencast.to">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://screencast.to/">
<link rel="icon" href="${FAVICON_HREF}">

<!-- Open Graph (Facebook, LinkedIn, iMessage, Slack) -->
<meta property="og:site_name" content="Screencast.to">
<meta property="og:title" content="Screencast.to — Temporary screen recordings for work">
<meta property="og:description" content="A tiny macOS menu-bar app. Record locally, then share a 24-hour link when you choose.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://screencast.to/">
<meta property="og:image" content="${OG_IMAGE_URL}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Screencast.to — temporary screen recordings for work">
<meta property="og:locale" content="en_US">

<!-- Twitter / X -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Screencast.to — Temporary screen recordings for work">
<meta name="twitter:description" content="Record locally, then share a 24-hour link when you choose.">
<meta name="twitter:image" content="${OG_IMAGE_URL}">

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
    <a class="btn btn-primary text-white" href="${DOWNLOAD_URL}" download>Download</a>
  </div>
</nav>

<main>

  <section class="hero">
    <span class="eyebrow">macOS · Local by default · 24h links</span>
    <h1>Screen recordings<br><span class="accent">that don't live forever.</span></h1>
    <p>A tiny menu-bar app for macOS. Capture locally, then upload only when you choose. Share a 24-hour link anyone can watch without an account.</p>
    <div class="cta">
      <a class="btn btn-primary btn-lg" href="${DOWNLOAD_URL}" download>
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
        <h3>Share when you choose</h3>
        <p>Recordings stay local until you upload. One click copies a 24-hour link your recipient can watch in a browser — no app, no login.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg></div>
        <h3>Temporary by design</h3>
        <p>Uploaded links auto-delete after 24 hours. Nothing becomes a permanent video library unless you keep the local file.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="14" rx="2"/><path d="M3 10h18"/><path d="M8 2v4"/><path d="M16 2v4"/></svg></div>
        <h3>Menu-bar native</h3>
        <p>No dock icon, no window clutter. One tiny status icon that gets out of your way until you need it.</p>
      </div>

      <div class="card">
        <div class="icon"><svg viewBox="0 0 24 24"><path d="M12 1v22"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg></div>
        <h3>Free</h3>
        <p>No accounts, no plans, no upsells. Build a habit without building another permanent video library.</p>
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
        <h3>Upload, copy, share</h3>
        <p>Click upload on a recording to copy a 24-hour link.</p>
      </div>
    </div>
  </section>

  <section class="install" id="install">
    <h2>Get ${BRAND}</h2>
    <p>Free. Record locally, share temporary links when you choose. macOS 15+.</p>
    <div class="row">
      <a class="btn btn-primary btn-lg" href="${DOWNLOAD_URL}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 3v12"/><path d="M7 10l5 5 5-5"/><path d="M5 21h14"/>
        </svg>
        Download .dmg
      </a>
    </div>
  </section>

</main>

<footer>
  <span>© ${new Date().getFullYear()} ${BRAND}</span>
  <span>Uploaded links auto-delete after 24 hours · <a href="/privacy">Privacy</a></span>
</footer>

</body>
</html>`;
}
