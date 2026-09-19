import { createReadStream } from 'node:fs';
import { realpath, stat } from 'node:fs/promises';
import { createServer } from 'node:http';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('../', import.meta.url)));
const port = Number(process.env.PORT || 4173);
const host = '127.0.0.1';
const publicPages = new Set([
  'index.html', 'confirmation.html', 'confirmation.js', 'checkout.js',
  'styles.css', 'support.html', 'robots.txt', 'sitemap.xml',
  'bundle/index.html',
]);
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.webp': 'image/webp', '.xml': 'application/xml' };

function finish(response, status, body = '') {
  response.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
  response.end(body);
}

export const server = createServer(async (request, response) => {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Referrer-Policy', 'no-referrer');
  try {
    const url = new URL(request.url, `http://${host}:${port}`);
    if (url.pathname === '/api/config') {
      if (request.method !== 'GET') { response.setHeader('Allow', 'GET'); return finish(response, 405, 'Method not allowed.'); }
      const body = JSON.stringify({ enabled: false, mode: null, price: null, downloadReady: false });
      response.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      return response.end(body);
    }
    if (url.pathname.startsWith('/api/')) return finish(response, 503, 'Cloudflare APIs are disabled in the static preview.');
    if (url.pathname === '/privacy' || url.pathname === '/privacy.html') {
      response.writeHead(302, { Location: '/policies/#privacy' });
      return response.end();
    }
    if (url.pathname === '/support') {
      response.writeHead(302, { Location: '/support.html' });
      return response.end();
    }
    if (!['GET', 'HEAD'].includes(request.method)) return finish(response, 405, 'Method not allowed.');
    let pathname = decodeURIComponent(url.pathname).replace(/^\/+/, '');
    if (pathname.includes('\\') || pathname.split('/').some((part) => part === '..' || part === '.' || part.startsWith('.'))) return finish(response, 404, 'Not found.');
    if (!pathname) pathname = 'index.html';
    if (pathname === 'bundle' || pathname === 'bundle/') pathname = 'bundle/index.html';
    if (pathname === 'policies' || pathname === 'policies/') pathname = 'policies/index.html';
    const filename = resolve(root, pathname);
    if (!filename.startsWith(root + sep) ||
        (!publicPages.has(pathname) && !pathname.startsWith('assets/') && pathname !== 'policies/index.html')) return finish(response, 404, 'Not found.');
    if (await realpath(filename) !== filename ||
        (pathname.startsWith('assets/') && !['.svg', '.png', '.jpg', '.webp'].includes(extname(filename)))) return finish(response, 404, 'Not found.');
    const { size } = await stat(filename);
    response.writeHead(200, {
      'Content-Type': types[extname(filename)] || 'application/octet-stream',
      'Content-Length': size,
      'Cache-Control': pathname === 'confirmation.html' ? 'private, no-store' : 'no-cache',
    });
    if (request.method === 'HEAD') return response.end();
    createReadStream(filename).pipe(response);
  } catch (error) {
    if (!response.headersSent) finish(response, error.code === 'ENOENT' ? 404 : 500, 'This request could not be completed.');
    else response.destroy();
  }
});
server.listen(port, host, () => console.log(`Screencast.to checkout: http://${host}:${port}`));
