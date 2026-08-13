import { copyFile, mkdir, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { renderHome } from "../src/views/home";
import { renderPrivacy } from "../src/views/privacy";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../..");
const siteRoot = resolve(repoRoot, "site");
const siteCname = process.env.SITE_CNAME?.trim();

await rm(siteRoot, { recursive: true, force: true });
await mkdir(resolve(siteRoot, "assets"), { recursive: true });
await mkdir(resolve(siteRoot, "privacy"), { recursive: true });

await writeFile(resolve(siteRoot, "index.html"), renderHome());
await writeFile(resolve(siteRoot, "privacy", "index.html"), renderPrivacy());
await writeFile(resolve(siteRoot, "404.html"), notFoundPage());
await writeFile(resolve(siteRoot, ".nojekyll"), "");
if (siteCname) {
  await writeFile(resolve(siteRoot, "CNAME"), `${siteCname}\n`);
}
await copyFile(
  resolve(repoRoot, ".github", "assets", "website.png"),
  resolve(siteRoot, "assets", "website.png")
);

function notFoundPage(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Not found - Screencast.to</title>
<style>
  body {
    margin: 0;
    min-height: 100vh;
    display: grid;
    place-items: center;
    background: #0a0c10;
    color: #e8eaed;
    font: 16px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
  }
  main { max-width: 440px; padding: 32px; text-align: center; }
  h1 { font-size: 28px; margin: 0 0 8px; }
  p { color: #b8bcc6; margin: 0 0 20px; }
  a { color: #fff; background: #ef4444; padding: 10px 14px; border-radius: 8px; text-decoration: none; font-weight: 600; }
</style>
</head>
<body>
<main>
  <h1>Not found</h1>
  <p>This page is not part of the static site.</p>
  <a href="/">Go home</a>
</main>
</body>
</html>`;
}
