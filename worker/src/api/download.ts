import type { Env } from "../env";
import { CORS } from "../views/shared";

/**
 * GET /download/<file> — 302 redirects to the R2 public URL for that file.
 * Files live under `downloads/` in the bucket. Used to serve the .dmg and
 * the og.png from the screencast.to custom domain.
 */
export function handleDownload(url: URL, env: Env): Response {
  const file = url.pathname.slice("/download/".length);
  if (!/^[a-zA-Z0-9._-]+$/.test(file) || file.startsWith(".")) {
    return new Response("Not found", { status: 404, headers: CORS });
  }
  const target = `https://${normalizeHost(env.R2_PUB_HOST)}/downloads/${file}`;
  return Response.redirect(target, 302);
}

function normalizeHost(host: string): string {
  return host.replace(/^https?:\/\//i, "").replace(/\/+$/, "");
}
