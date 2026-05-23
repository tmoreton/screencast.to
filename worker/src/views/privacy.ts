import { BRAND, FAVICON_HREF, GA_SNIPPET } from "./shared";

/** Privacy policy page at GET /privacy. */
export function renderPrivacy(): string {
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
