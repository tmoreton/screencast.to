import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { checkoutPresentation, mountCheckout } from '../checkout.js';
import { purchasePresentation } from '../confirmation.js';

function checkoutHarness(request) {
  function target() {
    const listeners = new Map();
    return {
      disabled: false, hidden: false, textContent: '', dataset: {},
      addEventListener(type, listener) { listeners.set(type, listener); },
      dispatch(type, event = {}) { return listeners.get(type)?.(event); },
    };
  }
  const nodes = Object.fromEntries([
    'checkout-form', 'checkout-button', 'checkout-status', 'checkout-notice', 'checkout-retry',
  ].map((id) => [id, target()]));
  const document = { getElementById: (id) => nodes[id], querySelectorAll: () => [] };
  const window = { ...target(), location: { search: '' } };
  return { nodes, window, checkout: mountCheckout(document, window, request) };
}

const readyCheckout = {
  enabled: true, mode: 'live', downloadReady: true,
  price: { amount: 2900, currency: 'usd', formatted: '$29.00' },
};

test('checkout presentation requires every server-side readiness signal', () => {
  const config = {
    enabled: true, mode: 'live', downloadReady: true,
    price: { amount: 2900, currency: 'usd', formatted: '$29.00' },
  };
  assert.deepEqual(checkoutPresentation(config), {
    enabled: true, mode: 'live', price: config.price,
    button: 'Buy Screencast.to — $29.00',
    status: 'One payment. Secure checkout by Stripe. Your private Mac download follows payment confirmation.',
  });
  for (const changed of [
    { ...config, enabled: false }, { ...config, downloadReady: false },
    { ...config, mode: null }, { ...config, price: null },
  ]) assert.equal(checkoutPresentation(changed).enabled, false);
});

test('returning from Stripe with browser Back restores checkout and allows another attempt', async () => {
  let checks = 0;
  const { nodes, window, checkout } = checkoutHarness(async () => {
    checks += 1;
    return Response.json(readyCheckout);
  });
  await checkout.ready;
  const button = nodes['checkout-button'];
  assert.equal(button.disabled, false);
  const submission = new Event('submit', { cancelable: true });
  nodes['checkout-form'].dispatch('submit', submission);
  assert.equal(submission.defaultPrevented, false);
  assert.equal(button.disabled, true);
  assert.equal(button.textContent, 'Opening secure checkout…');
  const duplicate = new Event('submit', { cancelable: true });
  nodes['checkout-form'].dispatch('submit', duplicate);
  assert.equal(duplicate.defaultPrevented, true);

  await window.dispatch('pageshow', { persisted: true });
  assert.equal(checks, 2);
  assert.equal(button.disabled, false);
  assert.equal(button.textContent, 'Buy Screencast.to — $29.00');
  const retried = new Event('submit', { cancelable: true });
  nodes['checkout-form'].dispatch('submit', retried);
  assert.equal(retried.defaultPrevented, false);
});

test('checkout stays retryable after a failed availability refresh on browser Back', async () => {
  let checks = 0;
  const { nodes, window, checkout } = checkoutHarness(async () => {
    checks += 1;
    return Response.json(readyCheckout, { status: checks === 2 ? 503 : 200 });
  });
  await checkout.ready;
  nodes['checkout-form'].dispatch('submit', new Event('submit', { cancelable: true }));
  await window.dispatch('pageshow', { persisted: true });
  assert.equal(nodes['checkout-button'].disabled, true);
  assert.equal(nodes['checkout-retry'].hidden, false);
  const unavailable = new Event('submit', { cancelable: true });
  nodes['checkout-form'].dispatch('submit', unavailable);
  assert.equal(unavailable.defaultPrevented, true);

  await nodes['checkout-retry'].dispatch('click');
  assert.equal(nodes['checkout-button'].disabled, false);
  assert.equal(nodes['checkout-retry'].hidden, true);
  const retried = new Event('submit', { cancelable: true });
  nodes['checkout-form'].dispatch('submit', retried);
  assert.equal(retried.defaultPrevented, false);
});

test('confirmation never reveals a download before verified paid status', () => {
  assert.equal(purchasePresentation({ paid: true, mode: 'live' }, 200).state, 'ready');
  assert.equal(purchasePresentation({ pending: true, mode: 'live' }, 202).state, 'pending');
  assert.equal(purchasePresentation({ paid: false, mode: 'live' }, 403).state, 'invalid');
  assert.equal(purchasePresentation({}, 502).state, 'error');
});

test('public website has checkout CTAs but no installer or GitHub release download', async () => {
  const index = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  assert.match(index, /action="\/api\/checkout"/);
  assert.doesNotMatch(index, /href="[^"]+\.dmg/);
  assert.doesNotMatch(index, /github\.com\/[^" ]+\/releases/);
  assert.match(index, /href="\/bundle\/"/);
  assert.doesNotMatch(index, /id="bundle"/);
});

test('bundle preview lives on a dedicated page with real product branding and no premature sale claim', async () => {
  const bundle = await readFile(new URL('../bundle/index.html', import.meta.url), 'utf8');
  assert.match(bundle, /Productivity Bundle/);
  assert.match(bundle, /YAPRFLOW/);
  assert.match(bundle, /yaprflow-mark\.svg/);
  assert.match(bundle, /NOT FOR SALE YET/);
  assert.doesNotMatch(bundle, /action="\/api\/checkout"/);
});
