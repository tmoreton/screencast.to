// Brand constants, analytics snippet, favicon, and small string utils used
// by every render*() view. Keep this file dependency-free.

export const BRAND = "Screencast.to";
export const DOWNLOAD_URL = "https://github.com/tmoreton/screencast.to/releases/latest/download/screencast.dmg";
export const GITHUB_URL = "https://github.com/tmoreton/screencast.to";
export const OG_IMAGE_URL = "https://screencast.to/assets/website.png";
export const PRIVACY_UPDATED = "2026-08-13";

// Optional Google Analytics 4 Measurement ID. Empty by default for public
// builds; set a value here only for a site deployment that intentionally uses GA.
export const GA_MEASUREMENT_ID = "";

export const GA_SNIPPET = GA_MEASUREMENT_ID ? `
<script async src="https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', '${GA_MEASUREMENT_ID}');
</script>` : "";

export const THEME_SCRIPT = `
<script>
(function() {
  var key = "screencast.theme";
  var root = document.documentElement;
  var mq = window.matchMedia("(prefers-color-scheme: dark)");

  function storedTheme() {
    try { return window.localStorage.getItem(key); } catch (_) { return ""; }
  }

  function saveTheme(theme) {
    try { window.localStorage.setItem(key, theme); } catch (_) {}
  }

  function applyTheme(theme) {
    if (theme === "light" || theme === "dark") {
      root.dataset.theme = theme;
    } else {
      root.removeAttribute("data-theme");
    }
  }

  function activeTheme() {
    return root.dataset.theme || (mq.matches ? "dark" : "light");
  }

  applyTheme(storedTheme());

  window.addEventListener("DOMContentLoaded", function() {
    var toggle = document.querySelector("[data-theme-toggle]");
    var label = document.querySelector("[data-theme-label]");
    var menuButton = document.querySelector("[data-menu-button]");
    var menu = document.querySelector("[data-nav-actions]");

    function paint() {
      var next = activeTheme() === "dark" ? "Light" : "Dark";
      if (label) label.textContent = next;
      if (toggle) toggle.setAttribute("aria-label", "Switch to " + next.toLowerCase() + " mode");
    }

    if (toggle) {
      toggle.addEventListener("click", function() {
        var next = activeTheme() === "dark" ? "light" : "dark";
        saveTheme(next);
        applyTheme(next);
        paint();
      });
    }

    function setMenu(open) {
      if (!menu || !menuButton) return;
      menu.dataset.open = open ? "true" : "false";
      menuButton.setAttribute("aria-expanded", open ? "true" : "false");
    }

    if (menuButton && menu) {
      menuButton.addEventListener("click", function() {
        setMenu(menu.dataset.open !== "true");
      });
      menu.addEventListener("click", function(event) {
        var target = event.target;
        if (target && target.closest && target.closest("a")) setMenu(false);
      });
      window.addEventListener("keydown", function(event) {
        if (event.key === "Escape") setMenu(false);
      });
      setMenu(false);
    }

    if (mq.addEventListener) mq.addEventListener("change", paint);
    paint();
  });
})();
</script>`;

// Inline SVG favicon — red squircle + white ring + white record dot.
// Mirrors the macOS app icon and the onboarding brand mark.
// All `"` inside the SVG are %22-encoded so the data URI doesn't break out
// of the HTML attribute it's interpolated into.
export const FAVICON_HREF = "data:image/svg+xml," +
  "<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 32 32%22>" +
  "<defs><linearGradient id=%22g%22 x1=%220%22 y1=%220%22 x2=%2232%22 y2=%2232%22 gradientUnits=%22userSpaceOnUse%22>" +
  "<stop offset=%220%22 stop-color=%22%23f64d4d%22/>" +
  "<stop offset=%221%22 stop-color=%22%23d12d2d%22/>" +
  "</linearGradient></defs>" +
  "<rect x=%222%22 y=%222%22 width=%2228%22 height=%2228%22 rx=%227%22 fill=%22url(%23g)%22/>" +
  "<circle cx=%2216%22 cy=%2216%22 r=%229.5%22 fill=%22none%22 stroke=%22%23fff%22 stroke-opacity=%220.95%22 stroke-width=%222.5%22/>" +
  "<circle cx=%2216%22 cy=%2216%22 r=%225.5%22 fill=%22%23fff%22/>" +
  "</svg>";

export function escapeHtml(s: string): string {
  const map: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  };
  return s.replace(/[&<>"']/g, (c) => map[c]!);
}

/** Shared HTTP response defaults used by every route. */
export const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Screencast-Auth",
};

export const HTML_HEADERS = {
  "Content-Type": "text/html; charset=utf-8",
  ...CORS,
};
