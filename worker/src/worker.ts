import type { Env } from "./env";
import { CORS, HTML_HEADERS } from "./views/shared";
import { renderHome } from "./views/home";
import { renderPrivacy } from "./views/privacy";
import { renderSupport } from "./views/support";
import { handleSign } from "./api/sign";
import { handleEntitlement } from "./api/entitlement";
import { handleViewer } from "./api/viewer";
import { handleDownload } from "./api/download";
import { handleCommerce } from "./commerce";
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
    const isShareHost = url.hostname === "share.screencast.to";

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

    // The sharing hostname keeps its purpose-built viewer and policy pages.
    if (isShareHost && url.pathname === "/" && isRead) {
      return new Response(renderHome(), { status: 200, headers: HTML_HEADERS });
    }
    if (isShareHost && url.pathname === "/privacy" && isRead) {
      return new Response(renderPrivacy(), { status: 200, headers: HTML_HEADERS });
    }
    if (isShareHost && url.pathname === "/support" && isRead) {
      return new Response(renderSupport(), { status: 200, headers: HTML_HEADERS });
    }

    if (!isShareHost) {
      const commerce = await handleCommerce(request, env);
      if (commerce) return commerce;

      if (url.hostname === "www.screencast.to") {
        url.hostname = "screencast.to";
        return new Response(null, { status: 308, headers: { Location: url.href } });
      }
      if (isRead && url.pathname === "/privacy") {
        return new Response(null, { status: 308, headers: { Location: "/policies/#privacy" } });
      }
      if (isRead && url.pathname === "/support") {
        return new Response(null, { status: 308, headers: { Location: "/support.html" } });
      }
      if (isRead && url.pathname === "/confirmation.html" && url.searchParams.has("session_id")) {
        url.pathname = "/api/complete";
        return handleCommerce(new Request(url, request), env) as Promise<Response>;
      }
      if (isRead) {
        const asset = await env.ASSETS.fetch(request);
        const headers = new Headers(asset.headers);
        headers.set("Content-Security-Policy", "default-src 'self'; base-uri 'none'; form-action 'self' https://checkout.stripe.com; frame-ancestors 'none'; object-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'");
        headers.set("Referrer-Policy", "no-referrer");
        headers.set("X-Content-Type-Options", "nosniff");
        headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
        if (url.pathname === "/confirmation.html") {
          headers.set("Cache-Control", "private, no-store, max-age=0");
          headers.set("X-Robots-Tag", "noindex, nofollow");
        }
        return new Response(asset.body, { status: asset.status, statusText: asset.statusText, headers });
      }
    }

    return new Response("Not found", { status: 404, headers: CORS });
  },
};
