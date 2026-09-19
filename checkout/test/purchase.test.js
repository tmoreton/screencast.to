import assert from 'node:assert/strict';
import test from 'node:test';

import { allowedPriceIds, checkoutProductMarker, isPaidMacPurchase, loadMacPurchase } from '../lib/purchase.js';
import { purchaseCookieHeader, requestedPurchaseSessionId } from '../lib/purchase-identity.js';

const sessionId = 'cs_test_1234567890abcdef';
const prices = new Set(['price_current']);
const paid = {
  id: sessionId, mode: 'payment', livemode: false, status: 'complete', payment_status: 'paid',
  metadata: { product: 'screencast-mac' },
  line_items: { has_more: false, data: [{ quantity: 1, price: { id: 'price_current' } }] },
};

test('purchase entitlement requires the exact product, price, quantity, and paid state', () => {
  assert.equal(checkoutProductMarker(), 'screencast-mac');
  assert.equal(isPaidMacPurchase(paid, prices), true);
  for (const session of [
    { ...paid, payment_status: 'unpaid' },
    { ...paid, metadata: { product: 'other' } },
    { ...paid, line_items: { has_more: false, data: [{ quantity: 2, price: { id: 'price_current' } }] } },
    { ...paid, line_items: { has_more: false, data: [{ quantity: 1, price: { id: 'price_old' } }] } },
  ]) assert.equal(isPaidMacPurchase(session, prices), false);
});

test('allowed prices include current and explicitly retained historical prices only', () => {
  assert.deepEqual([...allowedPriceIds({
    STRIPE_PRICE_ID: 'price_current', STRIPE_ALLOWED_PRICE_IDS: 'price_old,bad, price_legacy',
  })], ['price_current', 'price_old', 'price_legacy']);
});

test('Stripe retrieval validates session mode and catches missing resources', async () => {
  const stripe = { checkout: { sessions: { retrieve: async () => paid } } };
  assert.equal(await loadMacPurchase(stripe, sessionId, prices, 'test'), paid);
  assert.equal(await loadMacPurchase(stripe, sessionId, prices, 'live'), null);
  assert.equal(await loadMacPurchase(stripe, 'not-a-session', prices, 'test'), null);
  const missing = { checkout: { sessions: { retrieve: async () => {
    const error = new Error('missing'); error.code = 'resource_missing'; throw error;
  } } } };
  assert.equal(await loadMacPurchase(missing, sessionId, prices, 'test'), null);
});

test('purchase cookie is host-only, secure, HttpOnly, and recovered without exposing it to JavaScript', () => {
  const env = { NODE_ENV: 'production', VERCEL_ENV: 'production' };
  const request = new Request(`https://screencast.to/api/complete?session_id=${sessionId}`);
  const cookie = purchaseCookieHeader(request, sessionId, 'test', env);
  assert.match(cookie, /^__Host-screencast-purchase=/);
  assert.match(cookie, /; Path=\/; Max-Age=2592000; HttpOnly; SameSite=Lax; Secure$/);
  const clean = new Request('https://screencast.to/api/status', { headers: { Cookie: cookie } });
  assert.equal(requestedPurchaseSessionId(clean, 'test', env), sessionId);
  const invalidQuery = new Request('https://screencast.to/api/status?session_id=bad', { headers: { Cookie: cookie } });
  assert.equal(requestedPurchaseSessionId(invalidQuery, 'test', env), null);
});
