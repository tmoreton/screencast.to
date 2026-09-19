import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { checkoutPresentation } from '../checkout.js';
import { purchasePresentation } from '../confirmation.js';

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
