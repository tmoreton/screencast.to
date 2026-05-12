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

    // API routes
    if (url.pathname === "/sign" && request.method === "POST") {
      return handleSign(request, env);
    }
    if (url.pathname.startsWith("/v/") && request.method === "GET") {
      return handleViewer(url, env);
    }
    if (url.pathname.startsWith("/download/") && request.method === "GET") {
      return handleDownload(url, env);
    }

    // Pages
    if (url.pathname === "/" && request.method === "GET") {
      return new Response(renderHome(), { status: 200, headers: HTML_HEADERS });
    }
    if (url.pathname === "/privacy" && request.method === "GET") {
      return new Response(renderPrivacy(), { status: 200, headers: HTML_HEADERS });
    }

    return new Response("Not found", { status: 404, headers: CORS });
  },
};
