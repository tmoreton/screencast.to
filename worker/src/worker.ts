import type { Env } from "./env";
import { CORS, HTML_HEADERS } from "./views/shared";
import { renderHome } from "./views/home";
import { renderPrivacy } from "./views/privacy";
import { renderSupport } from "./views/support";
import { handleSign } from "./api/sign";
import { handleEntitlement } from "./api/entitlement";
import { handleViewer } from "./api/viewer";
import { handleDownload } from "./api/download";
import thirdPartyLicenses from "../THIRD_PARTY_LICENSES.txt";
import websiteImage from "../../.github/assets/website.png";
import appIcon from "../../screencast/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png";

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
    if (url.pathname === "/entitlements/token" && request.method === "POST") {
      return handleEntitlement(request, env);
    }
    if (url.pathname.startsWith("/v/") && isRead) {
      return handleViewer(url, env);
    }
    if (url.pathname.startsWith("/download/") && isRead) {
      return handleDownload(url, env);
    }
    if (url.pathname === "/assets/website.png" && isRead) {
      return new Response(websiteImage, {
        status: 200,
        headers: {
          "Content-Type": "image/png",
          "Cache-Control": "public, max-age=86400",
          ...CORS,
        },
      });
    }
    if (url.pathname === "/assets/icon.png" && isRead) {
      return new Response(appIcon, {
        status: 200,
        headers: {
          "Content-Type": "image/png",
          "Cache-Control": "public, max-age=86400",
          ...CORS,
        },
      });
    }
    if (url.pathname === "/third-party-licenses.txt" && isRead) {
      return new Response(thirdPartyLicenses, {
        status: 200,
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          "Cache-Control": "public, max-age=3600",
          ...CORS,
        },
      });
    }

    // Pages
    if (url.pathname === "/" && isRead) {
      return new Response(renderHome(), { status: 200, headers: HTML_HEADERS });
    }
    if (url.pathname === "/privacy" && isRead) {
      return new Response(renderPrivacy(), { status: 200, headers: HTML_HEADERS });
    }
    if (url.pathname === "/support" && isRead) {
      return new Response(renderSupport(), { status: 200, headers: HTML_HEADERS });
    }

    return new Response("Not found", { status: 404, headers: CORS });
  },
};
