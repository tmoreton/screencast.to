// Brand constants, analytics snippet, favicon, and small string utils used
// by every render*() view. Keep this file dependency-free.

export const BRAND = "Screencast.to";

// Google Analytics 4 Measurement ID for screencast.to.
// Get a new one at: https://analytics.google.com → Admin → Data Streams → your web stream.
export const GA_MEASUREMENT_ID = "G-WCRHYK4M00";

export const GA_SNIPPET = `
<script async src="https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', '${GA_MEASUREMENT_ID}');
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
