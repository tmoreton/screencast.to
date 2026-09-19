import assert from 'node:assert/strict';
import test from 'node:test';

import { createReleasePublisher } from '../lib/release-publishing.js';

const publishToken = 'release-publish-token-that-is-at-least-thirty-two-characters';
const environment = () => ({
  RELEASE_PUBLISH_TOKEN: publishToken,
  BLOB_READ_WRITE_TOKEN: 'vercel-blob-read-write-token',
});

function request(pathname, token = publishToken, type = 'blob.generate-client-token') {
  return new Request('https://screencast.to/api/publish', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ type, payload: { pathname, multipart: pathname.endsWith('.dmg') } }),
  });
}

test('release publishing requires the dedicated bearer token', async () => {
  const publish = createReleasePublisher({ environment, uploadHandler: async () => ({}) });
  assert.equal((await publish(request('releases/current.json', 'wrong-token'))).status, 401);
  assert.equal((await createReleasePublisher({
    environment: () => ({ ...environment(), RELEASE_PUBLISH_TOKEN: 'short' }),
    uploadHandler: async () => ({}),
  })(request('releases/current.json', 'short'))).status, 401);
});

test('release publishing grants short-lived upload access only to expected files', async () => {
  const calls = [];
  const publish = createReleasePublisher({
    environment,
    uploadHandler: async (options) => {
      calls.push(options);
      return { type: 'blob.generate-client-token', clientToken: 'short-lived-token' };
    },
  });

  const response = await publish(request('releases/screencast-3.0.0.dmg'));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).clientToken, 'short-lived-token');
  const policy = await calls[0].onBeforeGenerateToken();
  assert.deepEqual(policy.allowedContentTypes, ['application/x-apple-diskimage']);
  assert.equal(policy.addRandomSuffix, false);
  assert.equal(policy.allowOverwrite, false);
  assert.ok(policy.validUntil > Date.now());
  assert.ok(policy.validUntil <= Date.now() + 5 * 60 * 1000);
});

test('release publishing rejects unrelated paths, versions, and callback operations', async () => {
  const publish = createReleasePublisher({ environment, uploadHandler: async () => ({}) });
  assert.equal((await publish(request('private/customer-data.json'))).status, 400);
  assert.equal((await publish(request('releases/screencast-latest.dmg'))).status, 400);
  assert.equal((await publish(request('releases/current.json', publishToken, 'blob.upload-completed'))).status, 400);
});

