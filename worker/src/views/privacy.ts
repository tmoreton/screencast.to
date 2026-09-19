import { BRAND, FAVICON_HREF, GITHUB_URL, PRIVACY_UPDATED, SUPPORT_EMAIL, THEME_SCRIPT } from "./shared";

/** Privacy policy page at GET /privacy. */
export function renderPrivacy(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#f7f4ef" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0c0d0f" media="(prefers-color-scheme: dark)">
<title>Privacy — ${BRAND}</title>
<meta name="description" content="How Screencast.to handles local recordings, optional uploads, purchase verification, and network data.">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://screencast.to/privacy">
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
    --link: #b51f29;
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
      --link: #ff727a;
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
    --link: #ff727a;
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
    --link: #b51f29;
    --nav-bg: rgba(247,244,239,0.84);
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html { scroll-behavior: smooth; }
  body {
    background: var(--bg); color: var(--text); min-height: 100vh;
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
    position: sticky; top: 0; z-index: 20;
    display: flex; align-items: center; justify-content: space-between;
    padding: 18px 28px;
    border-bottom: 1px solid var(--border);
    background: var(--nav-bg);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
  }
  .brand { display: flex; align-items: center; gap: 9px; color: var(--text);
    font-weight: 600; letter-spacing: 0; }
  .brand .dot { width: 10px; height: 10px; border-radius: 50%;
    background: var(--accent); box-shadow: 0 0 14px var(--accent); }
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
  .menu-button {
    display: none;
    width: 38px;
    padding: 0;
  }
  .menu-button span {
    width: 16px;
    height: 2px;
    border-radius: 999px;
    background: currentColor;
    box-shadow: 0 5px 0 currentColor, 0 -5px 0 currentColor;
  }
  main { max-width: 720px; margin: 0 auto; padding: 56px 24px 80px; }
  main a { text-decoration: underline; text-underline-offset: 0.14em; }
  h1 { font-size: 36px; letter-spacing: 0; margin-bottom: 8px; }
  .lede { color: var(--text-2); margin-bottom: 8px; font-size: 17px; }
  .updated { color: var(--muted); font-size: 12px; margin-bottom: 40px; }
  h2 { font-size: 18px; letter-spacing: 0; margin-top: 36px; margin-bottom: 10px; }
  p, li { color: var(--text-2); }
  p { margin-bottom: 12px; }
  ul { padding-left: 22px; margin-bottom: 12px; }
  li { margin-bottom: 6px; }
  .tldr {
    background: var(--bg-elev);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 18px 22px;
    margin: 24px 0 8px;
  }
  .tldr h2 { margin-top: 0; color: var(--text); }
  code { background: var(--bg-elev); padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
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
    <a class="home-link" href="/support">Support</a>
    <a class="home-link" href="/">&larr; Home</a>
  </div>
</nav>
<main>
  <h1>Privacy</h1>
  <p class="lede">Plain language, no tricks.</p>
  <p class="updated">Last updated: ${PRIVACY_UPDATED}</p>

  <div class="tldr">
    <h2>TL;DR</h2>
    <p>${BRAND} records to your Mac. Nothing is uploaded unless you choose to create a temporary share link. There are no app accounts, analytics, advertising, tracking, or data sales. Optional uploads are normally deleted within 24–48 hours.</p>
  </div>

  <h2>What stays on your Mac</h2>
  <p>Recordings are created and kept locally by default. App preferences, including recording choices and saved local state, remain on your Mac. The website can save a light-or-dark theme preference in your browser's local storage; it is not sent to us.</p>

  <h2>What the service processes</h2>
  <ul>
    <li><strong>An optional uploaded recording.</strong> When you explicitly choose to share, the recording is sent to Cloudflare R2 and made available at a randomly generated link until deletion.</li>
    <li><strong>Anonymous purchase proof for official sharing.</strong> The App Store build sends an Apple-signed AppTransaction proof so the service can confirm that the app is entitled to use the optional hosted sharing service. The raw proof and Apple transaction identifiers are used only during verification; the ${BRAND} service does not store or log them.</li>
    <li><strong>Your network IP address for rate limiting.</strong> The upload and entitlement endpoints use it in a short-window rate limiter to reduce abuse. The ${BRAND} application does not add it to an account, analytics profile, or permanent database. Cloudflare may process network metadata as the infrastructure provider.</li>
    <li><strong>Support correspondence you choose to send.</strong> If you email support, the operator and email-delivery providers process your sender address, message, and any attachments only to answer the request, investigate abuse or security concerns, or remove a recording.</li>
  </ul>
  <p>The recorder and sharing service do not request or maintain a name, email address, or account profile. There are no ${BRAND} accounts. An email address is processed only when someone voluntarily contacts support.</p>

  <h2>Optional sharing</h2>
  <p>Uploaded recordings are stored in a Cloudflare R2 bucket operated for ${BRAND}. They are not listed in a public library, but anyone who has the specific share URL can watch the recording while it exists. Treat that URL like a secret and share it only with intended viewers.</p>

  <h2>Retention and deletion</h2>
  <p>A Cloudflare R2 lifecycle rule automatically deletes optional uploads, typically within <strong>24–48 hours</strong>. Lifecycle processing is not instantaneous, so deletion time can vary within that window. Once deleted, a recording cannot be recovered and its share link stops working.</p>
  <p>Purchase proofs are verified in transit and are not retained by the ${BRAND} service. The rate limiter retains only the short-lived state required to enforce its current window. Local recordings remain under your control until you delete them.</p>
  <p>Support correspondence is kept only while needed to resolve the request and is deleted within 90 days after resolution, unless a longer record is reasonably required for security, fraud prevention, or law. You can request earlier deletion by replying to the support conversation.</p>

  <h2>No analytics, cookies, or tracking</h2>
  <p>The Mac app, marketing site, privacy page, support page, and shared-recording viewer do not load analytics or advertising scripts. We do not use cookies or track you across sites. A theme choice may be saved locally in your browser so the site remembers light or dark mode; that preference never leaves your browser through our code.</p>

  <h2>Third parties</h2>
  <ul>
    <li><strong>Apple</strong> distributes the paid app and signs the AppTransaction proof used for anonymous entitlement verification. Apple handles App Store purchases under <a href="https://www.apple.com/legal/privacy/" target="_blank" rel="noopener noreferrer">Apple's Privacy Policy</a>.</li>
    <li><strong>Cloudflare</strong> runs the upload and entitlement worker, delivers shared recordings, stores optional uploads in R2, and applies network-level protections. See <a href="https://www.cloudflare.com/privacypolicy/" target="_blank" rel="noopener noreferrer">Cloudflare's Privacy Policy</a>.</li>
    <li><strong>Email providers</strong> route support messages to the operator's private mailbox and process only correspondence a person chooses to send. The public support alias uses <a href="https://www.namecheap.com/legal/general/privacy-policy/" target="_blank" rel="noopener noreferrer">Namecheap's email-forwarding infrastructure</a>; the private destination mailbox provider also processes that correspondence.</li>
    <li><strong>GitHub</strong> hosts the public source repository and issue tracker. If you visit GitHub or open an issue, GitHub processes that interaction under <a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement" target="_blank" rel="noopener noreferrer">GitHub's Privacy Statement</a>.</li>
  </ul>
  <p>When we share data with a service provider, we require it to use the data only for the purposes described here and to provide the same or equal protection promised by this policy and required by the App Store Review Guidelines.</p>
  <p>We do not sell personal data or provide uploaded recordings to advertisers or data brokers.</p>

  <h2>Your choices</h2>
  <p>You can use the recorder without the hosted sharing service. You can delete local files at any time, avoid uploading recordings, and wait for any existing upload to expire automatically. Because there is no account or service-side profile, there is no profile to close.</p>

  <h2>Support, privacy questions, and urgent removal</h2>
  <p>Email <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a> for support, privacy questions, consent withdrawal, or deletion requests. To request early deletion of an optional upload, include its temporary share URL so the recording can be located. Do not post a live private recording URL, purchase proof, or other sensitive information in a public GitHub issue.</p>

  <h2>Changes</h2>
  <p>This policy may be updated as the product evolves. The "Last updated" date at the top reflects the current version.</p>
</main>
<footer>
  <a href="/">${BRAND}</a> · <a href="/privacy">Privacy</a> · <a href="/support">Support</a> · <a href="mailto:${SUPPORT_EMAIL}">Email</a> · <a href="/third-party-licenses.txt">Licenses</a> · <a href="${GITHUB_URL}" target="_blank" rel="noopener noreferrer">Source</a>
</footer>
</body>
</html>`;
}
