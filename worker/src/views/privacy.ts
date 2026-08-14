import { BRAND, FAVICON_HREF, GA_SNIPPET, PRIVACY_UPDATED, THEME_SCRIPT } from "./shared";

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
<meta name="description" content="Screencast.to's privacy policy. Plain language, no tricks.">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://screencast.to/privacy">
<link rel="icon" href="${FAVICON_HREF}">
${GA_SNIPPET}
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
    --nav-bg: rgba(247,244,239,0.84);
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
  .theme-toggle {
    min-height: 36px;
    display: inline-flex;
    align-items: center;
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
  .theme-toggle:hover { border-color: var(--border-strong); }
  .theme-toggle::before {
    content: "";
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: linear-gradient(90deg, var(--accent) 0 50%, var(--border) 50% 100%);
    border: 1px solid var(--border-strong);
  }
  main { max-width: 720px; margin: 0 auto; padding: 56px 24px 80px; }
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
</style>
</head>
<body>
<nav>
  <a class="brand" href="/"><span class="dot"></span><span>${BRAND}</span></a>
  <div class="nav-actions">
    <button class="theme-toggle" type="button" data-theme-toggle><span data-theme-label>Theme</span></button>
    <a href="/" style="color: var(--text-2); font-size: 14px;">&larr; Home</a>
  </div>
</nav>
<main>
  <h1>Privacy</h1>
  <p class="lede">Plain language, no tricks.</p>
  <p class="updated">Last updated: ${PRIVACY_UPDATED}</p>

  <div class="tldr">
    <h2>TL;DR</h2>
    <p>${BRAND} records your screen locally on your Mac. If you choose to upload a recording, we store that file long enough to give you a 24-hour share link. Anyone with the link can watch until it expires. We don't watch, mine, or sell your recordings. Shared recording pages do not load analytics.</p>
  </div>

  <h2>What we collect</h2>
  <ul>
    <li><strong>Your screen recordings</strong>, stored locally on your Mac by default. If you choose to upload one, the file is stored on Cloudflare R2 (encrypted at rest) and accessible via a randomly-generated link.</li>
    <li><strong>Optional website analytics</strong> — the public build ships with analytics disabled. A hosted deployment may enable anonymous marketing-page analytics, but shared recording pages do not load analytics.</li>
    <li><strong>IP address</strong> on each recording-upload request, used only for short-window rate limiting (10 uploads / minute / IP). Not persisted.</li>
  </ul>
  <p>That's it. We don't collect your name, email, or any account info — there are no accounts.</p>

  <h2>Where your recordings live</h2>
  <p>Local recordings stay on your Mac until you upload them. Uploaded recordings are stored in a Cloudflare R2 bucket controlled by ${BRAND}. They are NOT publicly listed — only someone who has your specific share URL (which contains a random 10-character ID) can access the recording.</p>

  <h2>Auto-deletion</h2>
  <p>Every recording is deleted automatically <strong>within 24–48 hours</strong> of upload via a Cloudflare R2 lifecycle rule. After that, the share link returns a "Not Found" page. We can't recover deleted recordings.</p>

  <h2>Who can see your recording</h2>
  <p>Anyone who has the share URL can watch the recording until it auto-deletes. Treat the URL like a password — if it's shared publicly (e.g., on Twitter), the recording is effectively public. The viewer page doesn't require login.</p>

  <h2>Third parties</h2>
  <ul>
    <li><strong>Cloudflare</strong> — hosts the upload/share worker, stores recordings on R2, terminates TLS. <a href="https://www.cloudflare.com/privacypolicy/" target="_blank" rel="noopener">Their privacy policy</a>.</li>
    <li><strong>GitHub</strong> — hosts the static marketing pages and downloadable release assets. GitHub may log visitor IP addresses for security. <a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement" target="_blank" rel="noopener">Their privacy statement</a>.</li>
  </ul>
  <p>We don't share recordings or data with anyone else.</p>

  <h2>Cookies</h2>
  <p>The public site ships without analytics cookies. If a hosted deployment enables Google Analytics, only marketing/privacy pages load those cookies; shared recording pages do not. The Mac app itself uses no cookies.</p>

  <h2>Your rights</h2>
  <p>You can delete local recordings from your Mac at any time. Uploaded recordings expire automatically within 24–48 hours of upload. Since we don't have accounts, there's no profile to delete.</p>

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
