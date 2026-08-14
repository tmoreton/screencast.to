import type { Env } from "./env";
import { CORS, HTML_HEADERS } from "./views/shared";
import { renderHome } from "./views/home";
import { renderPrivacy } from "./views/privacy";
import { handleSign } from "./api/sign";
import { handleViewer } from "./api/viewer";
import { handleDownload } from "./api/download";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    const url = new URL(request.url);
    const isRead = request.method === "GET" || request.method === "HEAD";

    // API routes
    if (url.pathname === "/sign" && request.method === "POST") {
      return handleSign(request, env);
    }
    if (url.pathname.startsWith("/v/") && isRead) {
      return handleViewer(url, env);
    }
    if (url.pathname.startsWith("/download/") && isRead) {
      return handleDownload(url, env);
    }
    if (url.pathname === "/assets/website.png" && isRead) {
      return Response.redirect("https://raw.githubusercontent.com/tmoreton/screencast.to/main/.github/assets/website.png", 302);
    }
    if (url.pathname === "/assets/icon.png" && isRead) {
      return Response.redirect("https://raw.githubusercontent.com/tmoreton/screencast.to/main/screencast/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png", 302);
    }

    // Pages
    if (url.pathname === "/" && isRead) {
      return new Response(renderHome(), { status: 200, headers: HTML_HEADERS });
    }
    if (url.pathname === "/privacy" && isRead) {
      return new Response(renderPrivacy(), { status: 200, headers: HTML_HEADERS });
    }

    return new Response("Not found", { status: 404, headers: CORS });
  },
};
