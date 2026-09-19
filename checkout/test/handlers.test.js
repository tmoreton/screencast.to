import assert from 'node:assert/strict';
import test from 'node:test';

import { createHandlers } from '../lib/handlers.js';

const sessionId = 'cs_test_1234567890abcdef';
const updateToken = 'update-token-that-is-at-least-thirty-two-characters';
const privateUrl = 'https://store.private.blob.vercel-storage.com/releases/screencast-3.0.0.dmg?token=signed';
const env = {
  NODE_ENV: 'test', STRIPE_SECRET_KEY: 'sk_test_1234567890', STRIPE_PRICE_ID: 'price_current',
  CHECKOUT_ENABLED: 'true', CHECKOUT_BASE_URL: 'https://screencast.to',
  BLOB_READ_WRITE_TOKEN: 'blob-token', RELEASE_MANIFEST_PATH: 'releases/current.json',
  SPARKLE_UPDATE_TOKEN: updateToken,
};
const release = {
  product: 'screencast-mac', version: '3.0.0', pathname: 'releases/screencast-3.0.0.dmg',
  appcastPath: 'releases/appcast-3.0.0.xml', size: 1234, sha256: 'a'.repeat(64),
};
const price = {
  id: 'price_current', active: true, type: 'one_time', billing_scheme: 'per_unit',
  recurring: null, custom_unit_amount: null, transform_quantity: null, livemode: false,
  unit_amount: 2900, currency: 'usd', product: { active: true },
};
const paid = {
  id: sessionId, mode: 'payment', livemode: false, status: 'complete', payment_status: 'paid',
  metadata: { product: 'screencast-mac' },
  line_items: { has_more: false, data: [{ quantity: 1, price: { id: 'price_current' } }] },
};

function fixture({ environment = env, session = paid, manifest = release } = {}) {
  const calls = { sessions: [], prices: [], created: [], signed: [] };
  const stripe = {
    prices: { retrieve: async (...args) => { calls.prices.push(args); return price; } },
    checkout: { sessions: {
      retrieve: async (...args) => { calls.sessions.push(args); return session; },
      create: async (...args) => {
        calls.created.push(args);
        return { url: 'https://checkout.stripe.com/c/pay/cs_test_checkout' };
      },
    } },
  };
  const api = createHandlers({
    environment: () => environment,
    stripeFactory: () => stripe,
    loadManifest: async () => manifest,
    getBlob: async (pathname) => pathname === 'releases/appcast-3.0.0.xml'
      ? { statusCode: 200, stream: new Response('<rss/>').body } : null,
    signRelease: async (pathname) => { calls.signed.push(pathname); return new URL(privateUrl); },
    logger: { error() {} },
  });
  return { api, calls };
}

function request(path, cookie) {
  return new Request(`https://screencast.to/api/${path}`, cookie ? { headers: { Cookie: cookie } } : undefined);
}

test('configuration is enabled only when Stripe price and private release are both ready', async () => {
  const enabled = await (await fixture().api.config()).json();
  assert.deepEqual(enabled, {
    enabled: true, mode: 'test', price: { amount: 2900, currency: 'usd', formatted: '$29.00' },
    downloadReady: true,
  });
  const missing = await (await fixture({ manifest: null }).api.config()).json();
  assert.equal(missing.enabled, false);
  assert.equal(missing.downloadReady, false);
});

test('checkout creates one marked one-time purchase and redirects only to Stripe', async () => {
  const { api, calls } = fixture();
  const response = await api.checkout(new Request('https://screencast.to/api/checkout', {
    method: 'POST', headers: { Origin: 'https://screencast.to', 'Sec-Fetch-Site': 'same-origin' },
  }));
  assert.equal(response.status, 303);
  assert.equal(response.headers.get('Location'), 'https://checkout.stripe.com/c/pay/cs_test_checkout');
  const params = calls.created[0][0];
  assert.equal(params.mode, 'payment');
  assert.deepEqual(params.line_items, [{ price: 'price_current', quantity: 1 }]);
  assert.deepEqual(params.metadata, { product: 'screencast-mac' });
  assert.match(params.success_url, /\/api\/complete\?session_id=/);
  assert.equal((await api.checkout(new Request('https://screencast.to/api/checkout', {
    method: 'POST', headers: { Origin: 'https://malicious.example', 'Sec-Fetch-Site': 'cross-site' },
  }))).status, 403);
  assert.equal(calls.created.length, 1);
});

test('completion removes the session from the browser address and creates the secure purchase cookie', async () => {
  const response = await fixture().api.complete(new Request(`https://screencast.to/api/complete?session_id=${sessionId}`));
  assert.equal(response.status, 303);
  assert.equal(response.headers.get('Location'), '/confirmation.html');
  assert.match(response.headers.get('Set-Cookie'), /__Host-screencast-purchase=/);
});

test('paid cookie receives a five-minute private download while unpaid access is denied', async () => {
  const complete = await fixture().api.complete(new Request(`https://screencast.to/api/complete?session_id=${sessionId}`));
  const cookie = complete.headers.get('Set-Cookie');
  const { api, calls } = fixture();
  const response = await api.download(request('download', cookie));
  assert.equal(response.status, 303);
  assert.equal(response.headers.get('Location'), privateUrl);
  assert.deepEqual(calls.signed, ['releases/screencast-3.0.0.dmg']);
  assert.equal((await fixture().api.download(request('download'))).status, 403);
  assert.equal((await fixture({ session: { ...paid, payment_status: 'unpaid' } }).api.download(request('download', cookie))).status, 403);
});

test('Sparkle feed and archive require the shared release token and current filename', async () => {
  const { api } = fixture();
  const auth = { headers: { Authorization: `Bearer ${updateToken}` } };
  assert.equal((await api.appcast(new Request('https://screencast.to/api/appcast', auth))).status, 200);
  assert.equal((await api.appcast(new Request('https://screencast.to/api/appcast'))).status, 401);
  const update = await api.update(new Request('https://screencast.to/api/update?file=screencast-3.0.0.dmg', auth));
  assert.equal(update.status, 303);
  assert.equal(update.headers.get('Location'), privateUrl);
  assert.equal((await api.update(new Request('https://screencast.to/api/update?file=other.dmg', auth))).status, 404);
});
