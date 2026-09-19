import { upload } from '@vercel/blob/client';
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
const uploadOptions = (contentType, allowOverwrite, multipart = false) => ({
  access: 'private', addRandomSuffix: false, allowOverwrite, contentType, multipart,
  handleUploadUrl: publishUrl.href,
  headers: { Authorization: `Bearer ${process.env.RELEASE_PUBLISH_TOKEN}` },
});

const filename = `screencast-${version}.dmg`;
const pathname = `releases/${filename}`;
const appcastPathname = `releases/appcast-${version}.xml`;
const digest = createHash('sha256');
for await (const chunk of createReadStream(dmgPath)) digest.update(chunk);
const { size } = await stat(dmgPath);

await upload(pathname, await openAsBlob(dmgPath, { type: 'application/x-apple-diskimage' }),
  uploadOptions('application/x-apple-diskimage', false, true));
await upload(appcastPathname, await readFile(appcastPath),
  uploadOptions('application/xml', false));
const manifest = {
  product: 'screencast-mac', version, pathname, appcastPath: appcastPathname,
  size, sha256: digest.digest('hex'), publishedAt: new Date().toISOString(),
};
await upload('releases/current.json', JSON.stringify(manifest),
  uploadOptions('application/json', true));
console.log(`Published private Screencast.to ${version} release and current manifest.`);
