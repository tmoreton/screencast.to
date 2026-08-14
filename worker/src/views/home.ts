import { BRAND, DOWNLOAD_URL, FAVICON_HREF, GA_SNIPPET, GITHUB_URL, OG_IMAGE_URL, THEME_SCRIPT } from "./shared";

/** Landing page at GET /. */
export function renderHome(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#fbfbfa" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#08090b" media="(prefers-color-scheme: dark)">
<title>${BRAND} - Local-first Mac screen recorder</title>
<meta name="description" content="Screencast.to is an open-source macOS menu-bar recorder. Capture locally, then share an optional 24-hour link. No accounts, no permanent video library.">
<meta name="keywords" content="screen recorder, mac screen recording, loom alternative, free screen recorder, open source screen recorder, macOS, temporary video link">
<meta name="author" content="Screencast.to">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://screencast.to/">
<link rel="icon" href="${FAVICON_HREF}">

<meta property="og:site_name" content="Screencast.to">
<meta property="og:title" content="Screencast.to - Local-first Mac screen recorder">
<meta property="og:description" content="Record on your Mac. Share a 24-hour link only when you choose. Open source, local first, no accounts.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://screencast.to/">
<meta property="og:image" content="${OG_IMAGE_URL}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Screencast.to landing page">
<meta property="og:locale" content="en_US">

<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Screencast.to - Local-first Mac screen recorder">
<meta name="twitter:description" content="A tiny open-source Mac recorder for local captures and optional 24-hour share links.">
<meta name="twitter:image" content="${OG_IMAGE_URL}">

${GA_SNIPPET}
${THEME_SCRIPT}
<style>
  :root {
    color-scheme: light;
    --bg: #fbfbfa;
    --surface: #ffffff;
    --surface-2: #f4f4f2;
    --surface-3: #ececea;
    --ink: #101113;
    --ink-soft: #434852;
    --muted: #6d7380;
    --line: #e1e2df;
    --line-strong: #c6c8c3;
    --accent: #ff3b30;
    --accent-strong: #d92d24;
    --accent-soft: #fff0ee;
    --blue: #0a84ff;
    --green: #1f9d5a;
    --amber: #f7a51b;
    --button-text: #ffffff;
    --nav-bg: rgba(251,251,250,0.84);
    --shadow: rgba(16,17,19,0.12);
    --shadow-strong: rgba(16,17,19,0.2);
    --screen: #101318;
    --screen-2: #171b22;
    --screen-3: #222833;
    --screen-line: rgba(255,255,255,0.12);
    --screen-text: rgba(255,255,255,0.76);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      color-scheme: dark;
      --bg: #08090b;
      --surface: #111318;
      --surface-2: #171a20;
      --surface-3: #20242c;
      --ink: #f7f7f4;
      --ink-soft: #c5c9d1;
      --muted: #8f96a3;
      --line: #282d35;
      --line-strong: #3b414d;
      --accent: #ff4f47;
      --accent-strong: #ff746e;
      --accent-soft: rgba(255,79,71,0.14);
      --blue: #60aaff;
      --green: #55d98e;
      --amber: #ffc257;
      --button-text: #ffffff;
      --nav-bg: rgba(8,9,11,0.78);
      --shadow: rgba(0,0,0,0.44);
      --shadow-strong: rgba(0,0,0,0.62);
      --screen: #111318;
      --screen-2: #181c24;
      --screen-3: #222834;
      --screen-line: rgba(255,255,255,0.12);
      --screen-text: rgba(255,255,255,0.76);
    }
  }
  :root[data-theme="dark"] {
    color-scheme: dark;
    --bg: #08090b;
    --surface: #111318;
    --surface-2: #171a20;
    --surface-3: #20242c;
    --ink: #f7f7f4;
    --ink-soft: #c5c9d1;
    --muted: #8f96a3;
    --line: #282d35;
    --line-strong: #3b414d;
    --accent: #ff4f47;
    --accent-strong: #ff746e;
    --accent-soft: rgba(255,79,71,0.14);
    --blue: #60aaff;
    --green: #55d98e;
    --amber: #ffc257;
    --button-text: #ffffff;
    --nav-bg: rgba(8,9,11,0.78);
    --shadow: rgba(0,0,0,0.44);
    --shadow-strong: rgba(0,0,0,0.62);
    --screen: #111318;
    --screen-2: #181c24;
    --screen-3: #222834;
    --screen-line: rgba(255,255,255,0.12);
    --screen-text: rgba(255,255,255,0.76);
  }
  :root[data-theme="light"] {
    color-scheme: light;
    --bg: #fbfbfa;
    --surface: #ffffff;
    --surface-2: #f4f4f2;
    --surface-3: #ececea;
    --ink: #101113;
    --ink-soft: #434852;
    --muted: #6d7380;
    --line: #e1e2df;
    --line-strong: #c6c8c3;
    --accent: #ff3b30;
    --accent-strong: #d92d24;
    --accent-soft: #fff0ee;
    --blue: #0a84ff;
    --green: #1f9d5a;
    --amber: #f7a51b;
    --button-text: #ffffff;
    --nav-bg: rgba(251,251,250,0.84);
    --shadow: rgba(16,17,19,0.12);
    --shadow-strong: rgba(16,17,19,0.2);
    --screen: #101318;
    --screen-2: #171b22;
    --screen-3: #222833;
    --screen-line: rgba(255,255,255,0.12);
    --screen-text: rgba(255,255,255,0.76);
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
    box-shadow: 0 10px 22px rgba(255,59,48,0.24);
  }
  .nav-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .nav-link {
    min-height: 38px;
    display: inline-flex;
    align-items: center;
    color: var(--ink-soft);
    font-size: 14px;
    padding: 8px 10px;
  }
  .nav-link:hover { color: var(--ink); }
  .button, .theme-toggle, .menu-button {
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
    padding: 9px 13px;
    cursor: pointer;
  }
  .button:hover, .theme-toggle:hover, .menu-button:hover { border-color: var(--line-strong); }
  .button.primary {
    background: var(--ink);
    border-color: var(--ink);
    color: var(--bg);
    box-shadow: 0 16px 34px -22px var(--shadow-strong);
  }
  .button.primary:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--button-text);
  }
  .theme-toggle::before {
    content: "";
    width: 15px;
    height: 15px;
    border-radius: 50%;
    background: linear-gradient(90deg, var(--accent) 0 50%, var(--surface-3) 50% 100%);
    border: 1px solid var(--line-strong);
  }
  .menu-button {
    display: none;
    width: 40px;
    padding: 0;
  }
  .menu-button span {
    width: 16px;
    height: 2px;
    border-radius: 999px;
    background: currentColor;
    box-shadow: 0 5px 0 currentColor, 0 -5px 0 currentColor;
  }

  .hero {
    padding: 48px 0 58px;
    text-align: center;
  }
  .eyebrow {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 18px;
    color: var(--accent-strong);
    background: var(--accent-soft);
    border: 1px solid color-mix(in srgb, var(--accent) 22%, transparent);
    border-radius: 999px;
    padding: 7px 12px;
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
  }
  h1 {
    max-width: 790px;
    margin: 0 auto 18px;
    font-size: 58px;
    line-height: 1.02;
    font-weight: 820;
  }
  .hero-copy {
    max-width: 720px;
    margin: 0 auto;
    color: var(--ink-soft);
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
    color: var(--ink-soft);
    font-size: 13px;
    font-weight: 680;
  }
  .product {
    margin: 26px auto 0;
    max-width: 980px;
    text-align: left;
    border: 1px solid var(--line-strong);
    border-radius: 8px;
    background: var(--screen);
    box-shadow: 0 34px 90px -56px var(--shadow-strong), 0 1px 0 rgba(255,255,255,0.08) inset;
    overflow: hidden;
  }
  .product-top {
    height: 42px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 14px;
    border-bottom: 1px solid var(--screen-line);
    background: var(--screen-2);
  }
  .traffic { width: 11px; height: 11px; border-radius: 50%; background: #ff5f57; }
  .traffic:nth-child(2) { background: #febc2e; }
  .traffic:nth-child(3) { background: #28c840; }
  .product-title {
    margin-left: 8px;
    color: var(--screen-text);
    font-size: 12px;
    font-weight: 720;
  }
  .product-body {
    position: relative;
    min-height: 430px;
    padding: 28px;
    color: #f8f8f6;
  }
  .recording-surface {
    min-height: 310px;
    border: 1px solid var(--screen-line);
    border-radius: 8px;
    background: var(--screen-2);
    padding: 20px;
  }
  .workspace-bar {
    display: grid;
    grid-template-columns: 28px minmax(90px, 210px) 1fr 76px;
    align-items: center;
    gap: 12px;
    margin-bottom: 20px;
  }
  .avatar {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    background: linear-gradient(135deg, #59677a, #b7c1cd);
  }
  .line { height: 10px; border-radius: 999px; background: rgba(255,255,255,0.16); }
  .line.short { width: 70%; }
  .line.blue { background: color-mix(in srgb, var(--blue) 46%, transparent); }
  .line.green { background: color-mix(in srgb, var(--green) 56%, transparent); }
  .work-grid {
    display: grid;
    grid-template-columns: 1fr 1fr 1.15fr;
    gap: 12px;
  }
  .work-panel {
    min-height: 190px;
    border: 1px solid var(--screen-line);
    border-radius: 8px;
    background: rgba(255,255,255,0.045);
    padding: 14px;
  }
  .work-panel.large {
    display: flex;
    align-items: end;
    gap: 8px;
  }
  .work-panel h4 {
    margin: 0 0 14px;
    color: rgba(255,255,255,0.9);
    font-size: 13px;
  }
  .work-panel .line { margin-bottom: 13px; }
  .work-panel.large span {
    flex: 1;
    min-width: 8px;
    border-radius: 4px 4px 0 0;
    background: rgba(255,255,255,0.18);
  }
  .work-panel.large span:nth-child(3),
  .work-panel.large span:nth-child(5),
  .work-panel.large span:nth-child(8) {
    background: color-mix(in srgb, var(--accent) 70%, transparent);
  }
  .menu-panel {
    position: absolute;
    left: 48px;
    bottom: 38px;
    width: 306px;
    border: 1px solid var(--screen-line);
    border-radius: 8px;
    background: rgba(17,19,24,0.9);
    box-shadow: 0 24px 60px rgba(0,0,0,0.36);
    overflow: hidden;
    backdrop-filter: blur(16px);
  }
  .menu-head, .menu-row, .recording-row {
    display: flex;
    align-items: center;
    gap: 10px;
    border-bottom: 1px solid var(--screen-line);
    padding: 13px 14px;
  }
  .menu-head img { width: 24px; height: 24px; border-radius: 6px; }
  .menu-title { color: #fff; font-weight: 760; }
  .menu-sub { color: var(--screen-text); font-size: 12px; }
  .menu-row { justify-content: space-between; color: var(--screen-text); font-size: 13px; }
  .menu-row strong { color: #fff; font-weight: 720; }
  .start-button {
    margin: 14px;
    height: 42px;
    border-radius: 8px;
    background: var(--accent);
    display: grid;
    place-items: center;
    color: #fff;
    font-weight: 820;
  }
  .recording-row { border-bottom: 0; align-items: flex-start; }
  .recording-dot { width: 9px; height: 9px; margin-top: 6px; border-radius: 50%; background: var(--accent); }
  .upload { margin-left: auto; color: var(--green); font-weight: 820; font-size: 12px; }
  .control-bar {
    position: absolute;
    top: 94px;
    left: 50%;
    transform: translateX(-50%);
    min-width: 286px;
    height: 46px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    border-radius: 999px;
    border: 1px solid rgba(255,255,255,0.18);
    background: rgba(8,9,11,0.82);
    color: #fff;
    box-shadow: 0 18px 40px rgba(0,0,0,0.32);
    backdrop-filter: blur(14px);
    font-weight: 820;
  }
  .control-bar .pulse {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--amber);
    box-shadow: 0 0 16px color-mix(in srgb, var(--amber) 78%, transparent);
  }
  .camera {
    position: absolute;
    right: 48px;
    bottom: 42px;
    width: 108px;
    height: 108px;
    border-radius: 50%;
    border: 4px solid rgba(255,255,255,0.88);
    background: linear-gradient(145deg, #c1cad5, #56616f);
    display: grid;
    place-items: center;
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
    padding: 72px 0;
    border-top: 1px solid var(--line);
  }
  .section-head {
    max-width: 660px;
    margin-bottom: 28px;
  }
  .section-kicker {
    margin: 0 0 8px;
    color: var(--accent);
    font-size: 12px;
    font-weight: 820;
    text-transform: uppercase;
  }
  h2 {
    margin: 0 0 10px;
    font-size: 34px;
    line-height: 1.15;
  }
  .section-head p, .split p, .card p, .step p, .compact-copy {
    color: var(--ink-soft);
    margin: 0;
  }
  .cards {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 14px;
  }
  .card {
    min-height: 176px;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 8px;
    padding: 22px;
  }
  .card small {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    color: var(--muted);
    font-weight: 820;
    text-transform: uppercase;
    font-size: 11px;
    margin-bottom: 16px;
  }
  .card small::before {
    content: "";
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--accent);
  }
  .card:nth-child(2) small::before { background: var(--blue); }
  .card:nth-child(3) small::before { background: var(--green); }
  .card h3 {
    margin: 0 0 8px;
    font-size: 18px;
  }
  .feature-table {
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--surface);
    overflow: hidden;
  }
  .feature-row {
    display: grid;
    grid-template-columns: 220px 1fr;
    gap: 22px;
    padding: 18px 20px;
    border-bottom: 1px solid var(--line);
  }
  .feature-row:last-child { border-bottom: 0; }
  .feature-row strong { font-size: 15px; }
  .feature-row p { margin: 0; color: var(--ink-soft); }
  .steps {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 18px;
  }
  .step {
    border-left: 3px solid var(--accent);
    padding-left: 18px;
  }
  .step:nth-child(2) { border-left-color: var(--amber); }
  .step:nth-child(3) { border-left-color: var(--green); }
  .step strong {
    display: block;
    margin-bottom: 6px;
    font-size: 18px;
  }
  .split {
    display: grid;
    grid-template-columns: 0.88fr 1.12fr;
    gap: 34px;
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
    padding: 15px 16px;
    color: var(--ink-soft);
  }
  .checks strong { color: var(--ink); }
  .final-cta {
    text-align: center;
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--surface);
    padding: 44px 24px;
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
  footer a { color: var(--ink-soft); }
  footer a:hover { color: var(--ink); text-decoration: underline; }

  @media (max-width: 900px) {
    h1 { font-size: 50px; }
    .product-body { min-height: 0; }
    .work-grid { grid-template-columns: 1fr; }
    .work-panel.large { min-height: 130px; }
    .control-bar { top: 82px; }
    .menu-panel {
      position: relative;
      left: auto;
      bottom: auto;
      width: 100%;
      margin-top: 18px;
    }
    .camera {
      right: 32px;
      bottom: 210px;
      width: 92px;
      height: 92px;
    }
    .cards, .steps, .split { grid-template-columns: 1fr; }
  }
  @media (max-width: 720px) {
    .wrap { width: min(1120px, calc(100% - 28px)); }
    .nav-inner { height: 64px; position: relative; }
    .menu-button { display: inline-flex; }
    .nav-actions {
      position: absolute;
      top: calc(100% + 1px);
      left: 0;
      right: 0;
      display: none;
      flex-direction: column;
      align-items: stretch;
      gap: 8px;
      padding: 10px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--surface);
      box-shadow: 0 18px 48px -28px var(--shadow-strong);
    }
    .nav-actions[data-open="true"] { display: flex; }
    .nav-link, .button, .theme-toggle { width: 100%; justify-content: flex-start; }
    h1 { font-size: 42px; }
    h2 { font-size: 28px; }
    .hero { padding-top: 54px; text-align: left; }
    .eyebrow { max-width: 100%; }
    .hero-copy { font-size: 17px; max-width: 420px; margin-left: 0; margin-right: 0; }
    .cta-row, .facts { justify-content: flex-start; }
    .cta-row .button { justify-content: center; }
    .product { margin-top: 34px; }
    .product-body { padding: 16px; }
    .recording-surface { padding: 14px; }
    .workspace-bar { grid-template-columns: 28px 1fr; }
    .workspace-bar .line:nth-child(n+3) { display: none; }
    .work-panel:nth-child(2) { display: none; }
    .control-bar {
      position: static;
      transform: none;
      width: 100%;
      min-width: 0;
      margin: 14px 0 0;
      border-radius: 8px;
    }
    .camera { display: none; }
    .feature-row {
      grid-template-columns: 1fr;
      gap: 8px;
    }
    section { padding: 56px 0; }
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
    <button class="menu-button" type="button" data-menu-button aria-controls="site-menu" aria-expanded="false">
      <span aria-hidden="true"></span>
      <span class="sr-only">Open menu</span>
    </button>
    <div class="nav-actions" id="site-menu" data-nav-actions>
      <a class="nav-link" href="#advantages">Advantages</a>
      <a class="nav-link" href="#workflow">Workflow</a>
      <a class="nav-link" href="/privacy">Privacy</a>
      <button class="theme-toggle" type="button" data-theme-toggle><span data-theme-label>Theme</span></button>
      <a class="button" href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">GitHub</a>
      <a class="button primary" href="${DOWNLOAD_URL}" download>Download</a>
    </div>
  </div>
</nav>

<main>
  <section class="hero wrap">
    <div class="eyebrow">Open source. Local first. Temporary sharing.</div>
    <h1>A local-first Mac screen recorder.</h1>
    <p class="hero-copy">${BRAND} lives in your menu bar. Capture screen, camera, microphone, and system audio, then keep the file on your Mac or upload a 24-hour link when sharing is easier.</p>
    <div class="cta-row">
      <a class="button primary" href="${DOWNLOAD_URL}" download>Download for Mac</a>
      <a class="button" href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">View source</a>
    </div>
    <p class="fine-print">macOS 15+ &middot; Apple Silicon and Intel &middot; Apache-2.0</p>
    <ul class="facts">
      <li>No account required</li>
      <li>Files start local</li>
      <li>Share links expire</li>
      <li>Source is public</li>
    </ul>

    <div class="product" aria-label="Screencast.to recording workflow preview">
      <div class="product-top">
        <span class="traffic"></span><span class="traffic"></span><span class="traffic"></span>
        <span class="product-title">${BRAND} recording workflow</span>
      </div>
      <div class="product-body">
        <div class="recording-surface">
          <div class="workspace-bar">
            <div class="avatar"></div>
            <div class="line"></div>
            <div class="line short"></div>
            <div class="line blue"></div>
          </div>
          <div class="work-grid">
            <div class="work-panel">
              <h4>Bug report</h4>
              <div class="line"></div>
              <div class="line short"></div>
              <div class="line green"></div>
            </div>
            <div class="work-panel">
              <h4>Demo notes</h4>
              <div class="line"></div>
              <div class="line short"></div>
              <div class="line"></div>
            </div>
            <div class="work-panel large" aria-hidden="true">
              <span style="height:34%"></span>
              <span style="height:48%"></span>
              <span style="height:82%"></span>
              <span style="height:58%"></span>
              <span style="height:72%"></span>
              <span style="height:44%"></span>
              <span style="height:90%"></span>
              <span style="height:62%"></span>
            </div>
          </div>
        </div>
        <div class="control-bar"><span class="pulse"></span><span>00:03 &middot; camera warming up</span></div>
        <div class="menu-panel">
          <div class="menu-head">
            <img src="/assets/icon.png" alt="">
            <div>
              <div class="menu-title">Ready to record</div>
              <div class="menu-sub">Stored locally by default</div>
            </div>
          </div>
          <div class="menu-row"><span>Capture</span><strong>Screen + Camera</strong></div>
          <div class="menu-row"><span>Audio</span><strong>Mic + System</strong></div>
          <div class="menu-row"><span>Sharing</span><strong>24-hour link</strong></div>
          <div class="start-button">Start Recording</div>
          <div class="recording-row">
            <span class="recording-dot"></span>
            <div>
              <div class="menu-title">Screencast 2.0.1.mov</div>
              <div class="menu-sub">Saved on this Mac</div>
            </div>
            <span class="upload">Upload</span>
          </div>
        </div>
        <div class="camera"></div>
      </div>
    </div>
  </section>

  <section id="advantages">
    <div class="wrap">
      <div class="section-head">
        <p class="section-kicker">Why it is different</p>
        <h2>Fast screen recordings without the permanent workspace.</h2>
        <p>Most recording tools turn every clip into another cloud library. ${BRAND} keeps the default simple: record locally, share temporarily, and stay in control.</p>
      </div>
      <div class="cards">
        <article class="card">
          <small>Local first</small>
          <h3>Your recordings start on your Mac.</h3>
          <p>Nothing is uploaded while you record. Keep the file, move it, delete it, or share it only when you decide.</p>
        </article>
        <article class="card">
          <small>Transparent</small>
          <h3>Open source from app to upload worker.</h3>
          <p>The Swift app, Cloudflare Worker, and static site are public, so the product claims are inspectable.</p>
        </article>
        <article class="card">
          <small>Temporary</small>
          <h3>Share links are designed to disappear.</h3>
          <p>Uploaded recordings get a browser link for viewers and are removed automatically after the short sharing window.</p>
        </article>
      </div>
    </div>
  </section>

  <section>
    <div class="wrap split">
      <div>
        <p class="section-kicker">What it records</p>
        <h2>Everything you need for a useful walkthrough.</h2>
        <p class="compact-copy">Use it for bug reports, customer demos, design notes, async updates, or quick “look at this” clips that do not need a team workspace.</p>
      </div>
      <div class="feature-table">
        <div class="feature-row">
          <strong>Screen and region capture</strong>
          <p>Record a whole display or draw a focused region around the work.</p>
        </div>
        <div class="feature-row">
          <strong>Camera, mic, and system audio</strong>
          <p>Add presence and context without configuring a heavy studio setup.</p>
        </div>
        <div class="feature-row">
          <strong>Camera warm-up countdown</strong>
          <p>Camera recordings wait before capture starts, so the first frame is already ready.</p>
        </div>
        <div class="feature-row">
          <strong>Browser viewer links</strong>
          <p>Share with anyone who has the URL. Viewers do not need to install anything or create an account.</p>
        </div>
      </div>
    </div>
  </section>

  <section id="workflow">
    <div class="wrap">
      <div class="section-head">
        <p class="section-kicker">Workflow</p>
        <h2>Three steps, then back to work.</h2>
      </div>
      <div class="steps">
        <div class="step">
          <strong>1. Pick a capture mode.</strong>
          <p>Choose screen, region, camera layout, microphone, and system audio from the menu bar.</p>
        </div>
        <div class="step">
          <strong>2. Record locally.</strong>
          <p>The file is written to your Mac first, with no sign-in flow or remote library in the way.</p>
        </div>
        <div class="step">
          <strong>3. Share only if needed.</strong>
          <p>Upload for a temporary link, or keep the recording local and send the file however you prefer.</p>
        </div>
      </div>
    </div>
  </section>

  <section>
    <div class="wrap split">
      <div>
        <p class="section-kicker">Privacy posture</p>
        <h2>Built for recordings you do not want hanging around.</h2>
        <p>${BRAND} is intentionally small: no accounts, no feed, no searchable team vault, and no permanent hosted archive.</p>
      </div>
      <ul class="checks">
        <li><strong>Local by default:</strong> recording and saving happen on your Mac before any upload exists.</li>
        <li><strong>No viewer login:</strong> people with the link can watch in the browser until it expires.</li>
        <li><strong>Short-lived uploads:</strong> shared files are deleted automatically by the Cloudflare R2 lifecycle rule.</li>
        <li><strong>Open implementation:</strong> review the app and server code on GitHub.</li>
      </ul>
    </div>
  </section>

  <section>
    <div class="wrap final-cta">
      <h2>Download ${BRAND}</h2>
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
    <span>Local first &middot; Open source &middot; 24-hour links &middot; <a href="/privacy">Privacy</a> &middot; <a href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">GitHub</a></span>
  </div>
</footer>

</body>
</html>`;
}
