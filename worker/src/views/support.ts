import { BRAND, FAVICON_HREF, GITHUB_URL, SUPPORT_EMAIL, THEME_SCRIPT } from "./shared";

const ISSUES_URL = `${GITHUB_URL}/issues`;
const MAINTAINER_URL = "https://github.com/tmoreton";

/** Support page at GET /support. */
export function renderSupport(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#f7f4ef" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0c0d0f" media="(prefers-color-scheme: dark)">
<title>Support — ${BRAND}</title>
<meta name="description" content="Help with recording, permissions, optional sharing, privacy, and App Store purchases in Screencast.to.">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://screencast.to/support">
<link rel="icon" href="${FAVICON_HREF}">
${THEME_SCRIPT}
<style>
  :root {
    color-scheme: light;
    --bg: #f7f4ef;
    --bg-elev: #fffaf4;
    --border: #d4cabd;
    --border-strong: #b9aa99;
    --text: #191613;
    --text-2: #4e463e;
    --muted: #756b61;
    --accent: #e9363f;
    --accent-strong: #c9252e;
    --link: #b51f29;
    --button-bg: #c9252e;
    --button-bg-hover: #a91b24;
    --button-text: #fff;
    --nav-bg: rgba(247,244,239,0.84);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      color-scheme: dark;
      --bg: #0c0d0f;
      --bg-elev: #15171b;
      --border: #2b3038;
      --border-strong: #3c424d;
      --text: #f4f1ec;
      --text-2: #d0c8bd;
      --muted: #9b9389;
      --accent: #ff4b55;
      --accent-strong: #ff727a;
      --link: #ff727a;
      --button-bg: #ff727a;
      --button-bg-hover: #ff9298;
      --button-text: #191613;
      --nav-bg: rgba(12,13,15,0.78);
    }
  }
  :root[data-theme="dark"] {
    color-scheme: dark;
    --bg: #0c0d0f;
    --bg-elev: #15171b;
    --border: #2b3038;
    --border-strong: #3c424d;
    --text: #f4f1ec;
    --text-2: #d0c8bd;
    --muted: #9b9389;
    --accent: #ff4b55;
    --accent-strong: #ff727a;
    --link: #ff727a;
    --button-bg: #ff727a;
    --button-bg-hover: #ff9298;
    --button-text: #191613;
    --nav-bg: rgba(12,13,15,0.78);
  }
  :root[data-theme="light"] {
    color-scheme: light;
    --bg: #f7f4ef;
    --bg-elev: #fffaf4;
    --border: #d4cabd;
    --border-strong: #b9aa99;
    --text: #191613;
    --text-2: #4e463e;
    --muted: #756b61;
    --accent: #e9363f;
    --accent-strong: #c9252e;
    --link: #b51f29;
    --button-bg: #c9252e;
    --button-bg-hover: #a91b24;
    --button-text: #fff;
    --nav-bg: rgba(247,244,239,0.84);
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    min-height: 100vh;
    background: var(--bg);
    color: var(--text);
    font: 16px/1.65 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  a { color: var(--link); text-decoration: none; }
  a:hover { text-decoration: underline; }
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
    z-index: 20;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 18px 28px;
    border-bottom: 1px solid var(--border);
    background: var(--nav-bg);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
  }
  .brand { display: flex; align-items: center; gap: 9px; color: var(--text); font-weight: 600; }
  .brand .dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--accent);
    box-shadow: 0 0 14px var(--accent);
  }
  .nav-actions { display: flex; align-items: center; gap: 8px; }
  .home-link { color: var(--text-2); font-size: 14px; }
  .theme-toggle, .menu-button {
    min-height: 36px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    border-radius: 8px;
    border: 1px solid var(--border);
    background: var(--bg-elev);
    color: var(--text);
    font: inherit;
    font-size: 13px;
    font-weight: 700;
    padding: 7px 11px;
    cursor: pointer;
  }
  .theme-toggle:hover, .menu-button:hover { border-color: var(--border-strong); }
  .theme-toggle::before {
    content: "";
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: linear-gradient(90deg, var(--accent) 0 50%, var(--border) 50% 100%);
    border: 1px solid var(--border-strong);
  }
  .menu-button { display: none; width: 38px; padding: 0; }
  .menu-button span {
    width: 16px;
    height: 2px;
    border-radius: 999px;
    background: currentColor;
    box-shadow: 0 5px 0 currentColor, 0 -5px 0 currentColor;
  }
  main { max-width: 780px; margin: 0 auto; padding: 56px 24px 80px; }
  main a:not(.button) { text-decoration: underline; text-underline-offset: 0.14em; }
  h1 { font-size: 36px; line-height: 1.1; margin-bottom: 8px; }
  .lede { max-width: 650px; color: var(--text-2); font-size: 17px; margin-bottom: 32px; }
  .support-grid { display: grid; gap: 14px; }
  .support-card {
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--bg-elev);
    padding: 22px;
  }
  h2 { font-size: 19px; line-height: 1.3; margin-bottom: 9px; }
  p, li { color: var(--text-2); }
  p + p { margin-top: 10px; }
  ul { margin: 10px 0 0; padding-left: 22px; }
  li + li { margin-top: 6px; }
  .actions { display: flex; flex-wrap: wrap; gap: 9px; margin-top: 18px; }
  .button {
    min-height: 40px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--bg);
    color: var(--text);
    padding: 8px 13px;
    font-size: 14px;
    font-weight: 700;
    text-decoration: none;
  }
  .button:hover { border-color: var(--border-strong); text-decoration: none; }
  .button.primary { background: var(--button-bg); border-color: var(--button-bg); color: var(--button-text); }
  .button.primary:hover { background: var(--button-bg-hover); border-color: var(--button-bg-hover); }
  .note { color: var(--muted); font-size: 13px; }
  footer { border-top: 1px solid var(--border); padding: 24px; color: var(--muted); font-size: 13px; text-align: center; }
  footer a { color: var(--text-2); }
  @media (max-width: 640px) {
    nav { padding: 14px; }
    .menu-button { display: inline-flex; }
    .nav-actions {
      position: absolute;
      top: calc(100% + 1px);
      left: 14px;
      right: 14px;
      display: none;
      flex-direction: column;
      align-items: stretch;
      gap: 8px;
      padding: 10px;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: var(--bg-elev);
      box-shadow: 0 18px 48px -28px rgba(0,0,0,0.32);
    }
    .nav-actions[data-open="true"] { display: flex; }
    .theme-toggle, .home-link { width: 100%; justify-content: flex-start; }
    .actions { display: grid; }
  }
</style>
</head>
<body>
<nav>
  <a class="brand" href="/"><span class="dot"></span><span>${BRAND}</span></a>
  <button class="menu-button" type="button" data-menu-button aria-controls="site-menu" aria-expanded="false">
    <span aria-hidden="true"></span>
    <span class="sr-only">Open menu</span>
  </button>
  <div class="nav-actions" id="site-menu" data-nav-actions>
    <button class="theme-toggle" type="button" data-theme-toggle><span data-theme-label>Theme</span></button>
    <a class="home-link" href="/privacy">Privacy</a>
    <a class="home-link" href="/">&larr; Home</a>
  </div>
</nav>
<main>
  <h1>Support</h1>
  <p class="lede">Help with ${BRAND}, from first recording to optional sharing. You do not need a ${BRAND} account to use the app or ask for help.</p>

  <div class="support-grid">
    <section class="support-card">
      <h2>Recording and permissions</h2>
      <p>${BRAND} needs macOS Screen Recording access to capture your screen. Camera and microphone access are optional and needed only when you choose those inputs.</p>
      <p>If an input is unavailable, review the app's access under <strong>System Settings → Privacy &amp; Security</strong>, then reopen ${BRAND} after changing a permission.</p>
    </section>

    <section class="support-card">
      <h2>Local files and optional sharing</h2>
      <p>Recordings are saved locally first. Uploading is a separate, explicit action that creates a temporary link; uploads are normally deleted within 24–48 hours.</p>
      <p>If sharing fails, confirm that the Mac is online and retry. The App Store build verifies an anonymous Apple-signed purchase proof for access to the official sharing service, but it does not create a ${BRAND} account.</p>
    </section>

    <section class="support-card">
      <h2>Report a bug or request help</h2>
      <p>Email <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a> for private support, privacy questions, or a recording-removal request. For a software bug that can be discussed publicly, search the issue tracker first, then open an issue with your ${BRAND} version, macOS version, the steps you took, and what happened.</p>
      <p class="note">GitHub issues are public. Do not include a private recording link, an AppTransaction proof, credentials, or a sensitive recording.</p>
      <div class="actions">
        <a class="button primary" href="mailto:${SUPPORT_EMAIL}">Email support</a>
        <a class="button" href="${ISSUES_URL}" target="_blank" rel="noopener noreferrer">Open GitHub Issues</a>
        <a class="button" href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">View source</a>
        <a class="button" href="${MAINTAINER_URL}" target="_blank" rel="noopener noreferrer">Maintainer profile</a>
      </div>
    </section>

    <section class="support-card">
      <h2>Purchases and privacy</h2>
      <p>Apple handles App Store billing and purchase history. For an Apple billing or refund issue, use <a href="https://reportaproblem.apple.com/" target="_blank" rel="noopener noreferrer">Apple's Report a Problem service</a>.</p>
      <p>For details about recordings, entitlement verification, retention, and service providers, read the <a href="/privacy">privacy policy</a>. For an urgent removal request, email <a href="mailto:${SUPPORT_EMAIL}?subject=Urgent%20recording%20removal">${SUPPORT_EMAIL}</a> with the temporary share URL and the reason for the request. Do not post the URL publicly.</p>
    </section>
  </div>
</main>
<footer>
  <a href="/">${BRAND}</a> · <a href="/privacy">Privacy</a> · <a href="/support">Support</a> · <a href="mailto:${SUPPORT_EMAIL}">Email</a> · <a href="/third-party-licenses.txt">Licenses</a> · <a href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">Source</a>
</footer>
</body>
</html>`;
}
