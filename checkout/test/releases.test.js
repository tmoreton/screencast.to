import assert from 'node:assert/strict';
import test from 'node:test';

import { hasUpdateAuthorization, loadReleaseManifest } from '../lib/releases.js';

const token = 'update-token-that-is-at-least-thirty-two-characters';
const manifest = {
  product: 'screencast-mac', version: '3.0.0',
  pathname: 'releases/screencast-3.0.0.dmg', appcastPath: 'releases/appcast-3.0.0.xml',
  size: 123456, sha256: 'a'.repeat(64), publishedAt: '2026-09-19T00:00:00.000Z',
};

function blob(value) {
  return { statusCode: 200, stream: new Response(JSON.stringify(value)).body };
}

test('release manifest accepts only the fixed product and version-derived private path', async () => {
  const env = { BLOB_READ_WRITE_TOKEN: 'blob-token', RELEASE_MANIFEST_PATH: 'releases/current.json' };
  assert.deepEqual(await loadReleaseManifest(env, async () => blob(manifest)), manifest);
  for (const changed of [
    { ...manifest, product: 'other' },
    { ...manifest, pathname: 'releases/other.dmg' },
    { ...manifest, appcastPath: '../appcast.xml' },
    { ...manifest, sha256: 'bad' },
    { ...manifest, size: 0 },
  ]) assert.equal(await loadReleaseManifest(env, async () => blob(changed)), null);
});

test('updater endpoints require an exact bearer token and reject short server tokens', () => {
  assert.equal(hasUpdateAuthorization(new Request('https://example.com', {
    headers: { Authorization: `Bearer ${token}` },
  }), { SPARKLE_UPDATE_TOKEN: token }), true);
  assert.equal(hasUpdateAuthorization(new Request('https://example.com', {
    headers: { Authorization: 'Bearer wrong' },
  }), { SPARKLE_UPDATE_TOKEN: token }), false);
  assert.equal(hasUpdateAuthorization(new Request('https://example.com', {
    headers: { Authorization: 'Bearer short' },
  }), { SPARKLE_UPDATE_TOKEN: 'short' }), false);
});
