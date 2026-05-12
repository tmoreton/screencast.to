import type { Env } from "../env";
import { CORS, HTML_HEADERS } from "../views/shared";
import { renderViewer } from "../views/viewer";

/**
 * GET /v/<id>.<ext> — renders the cinematic viewer page that plays the
 * recording from the R2 public host. The `<id>.<ext>` is validated against
 * a strict pattern so the route can't be used to craft arbitrary URLs.
 */
export function handleViewer(url: URL, env: Env): Response {
  const filename = url.pathname.slice("/v/".length);
  if (!/^[a-zA-Z0-9]{6,16}\.[a-zA-Z0-9]+$/.test(filename)) {
    return new Response("Not found", { status: 404, headers: CORS });
  }
  const videoUrl = `https://${normalizeHost(env.R2_PUB_HOST)}/recordings/${filename}`;
  return new Response(renderViewer(videoUrl), {
    status: 200,
    headers: HTML_HEADERS,
  });
}

function normalizeHost(host: string): string {
  return host.replace(/^https?:\/\//i, "").replace(/\/+$/, "");
}
