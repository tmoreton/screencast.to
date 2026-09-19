import { createHash } from 'node:crypto';
import { createReadStream, openAsBlob } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';

const [version, dmgPath, appcastPath] = process.argv.slice(2);
if (!/^[1-9][0-9]{0,3}\.(?:0|[1-9][0-9]?)\.(?:0|[1-9][0-9]?)$/.test(version || '') ||
    !dmgPath || !appcastPath) {
  throw new Error('usage: publish-release.mjs VERSION DMG_PATH APPCAST_PATH');
}
if (!process.env.RELEASE_PUBLISH_TOKEN || process.env.RELEASE_PUBLISH_TOKEN.length < 32) {
  throw new Error('RELEASE_PUBLISH_TOKEN must contain at least 32 characters');
}
const publishUrl = new URL(process.env.RELEASE_PUBLISH_URL || 'https://screencast.to/api/publish');
if (publishUrl.protocol !== 'https:' || publishUrl.username || publishUrl.password) {
  throw new Error('RELEASE_PUBLISH_URL must be an HTTPS URL without embedded credentials');
}
async function upload(pathname, body, contentType, size, sha256) {
  const target = new URL(publishUrl);
  target.searchParams.set('path', pathname);
  const headers = {
    Authorization: `Bearer ${process.env.RELEASE_PUBLISH_TOKEN}`,
    'Content-Length': String(size),
    'Content-Type': contentType,
  };
  if (sha256) headers['X-Release-SHA256'] = sha256;
  const response = await fetch(target, { method: 'PUT', headers, body });
  if (!response.ok) {
    const message = (await response.text()).slice(0, 500);
    throw new Error(`Release upload failed for ${pathname} (${response.status}): ${message}`);
  }
}

const filename = `screencast-${version}.dmg`;
const pathname = `releases/${filename}`;
const appcastPathname = `releases/appcast-${version}.xml`;
const digest = createHash('sha256');
for await (const chunk of createReadStream(dmgPath)) digest.update(chunk);
const { size } = await stat(dmgPath);
const sha256 = digest.digest('hex');
const dmg = await openAsBlob(dmgPath, { type: 'application/x-apple-diskimage' });
const appcast = await readFile(appcastPath);

await upload(pathname, dmg, 'application/x-apple-diskimage', size, sha256);
await upload(appcastPathname, appcast, 'application/xml', appcast.byteLength);
const manifest = {
  product: 'screencast-mac', version, pathname, appcastPath: appcastPathname,
  size, sha256, publishedAt: new Date().toISOString(),
};
const manifestBody = JSON.stringify(manifest);
await upload('releases/current.json', manifestBody, 'application/json', Buffer.byteLength(manifestBody));
console.log(`Published private Screencast.to ${version} release and current manifest to Cloudflare R2.`);
