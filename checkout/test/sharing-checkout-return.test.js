import assert from 'node:assert/strict';
import test from 'node:test';
import { mountSharing } from '../connect-sharing.js';
import { mountConfirmation } from '../confirmation.js';
import { clearPendingSharing, pendingSharingURL, rememberPendingSharing } from '../sharing-pending.js';

const context = { codeChallenge: 'C'.repeat(43), state: 'S'.repeat(43) };
const query = `?code_challenge=${context.codeChallenge}&state=${context.state}`;
const connectionURL = `/connect-sharing.html${query}`;
const maxAge = 15 * 60 * 1000;

function storage() {
  const values = new Map();
  return {
    values,
    getItem(key) { return values.get(key) ?? null; },
    setItem(key, value) { values.set(key, value); },
    removeItem(key) { values.delete(key); },
  };
}

function page(path, sessionStorage) {
  function target() {
    const listeners = new Map();
    return {
      hidden: true, disabled: false, textContent: '', value: '',
      addEventListener(type, listener) { listeners.set(type, listener); },
      dispatch(type, event = {}) { return listeners.get(type)?.(event); },
      removeAttribute(name) { delete this[name]; },
      reportValidity() { return true; },
    };
  }
  const ids = ['status', 'ready', 'help', 'download', 'retry', 'test-badge', 'continue-sharing',
    'sharing-next-steps', 'sharing-status', 'sharing-test', 'sharing-connect', 'sharing-open',
    'sharing-recovery', 'sharing-email', 'sharing-send', 'sharing-retry',
    'sharing-download', 'sharing-start-again'];
  const nodes = Object.fromEntries(ids.map((id) => [id, target()]));
  const url = new URL(path, 'https://screencast.to');
  const window = {
    ...target(), sessionStorage, location: { href: url.href, search: url.search },
    clearTimeout() {}, setTimeout() { return 1; },
    history: { replaceState() {} },
  };
  return { nodes, window, document: { getElementById: (id) => nodes[id] } };
}

test('only validated public binding values and their timestamp survive checkout', () => {
  const sessionStorage = storage();
  const window = { sessionStorage };
  const now = Date.now();
  assert.equal(rememberPendingSharing(window, {
    ...context, restore: 'private-restore-token', codeVerifier: 'private-verifier',
    callbackCode: 'private-code', session: 'private-purchase-id',
  }, now), true);
  assert.equal(sessionStorage.values.size, 1);
  const saved = JSON.parse([...sessionStorage.values.values()][0]);
  assert.deepEqual(saved, { ...context, createdAt: now });
  assert.equal(pendingSharingURL(window, now), connectionURL);
});

test('expired, future, malformed and extra-field pending contexts fail closed and are removed', () => {
  const now = Date.now();
  for (const invalid of [
    { ...context, createdAt: now - maxAge }, { ...context, createdAt: now + 1 },
    { ...context, createdAt: -1 }, { ...context, createdAt: 'today' },
    { ...context, createdAt: now, state: 'short' },
    { ...context, createdAt: now, codeChallenge: 'invalid' },
    { ...context, createdAt: now, restore: 'must-not-be-retained' }, null, [], 'bad-json',
  ]) {
    const sessionStorage = storage();
    const window = { sessionStorage };
    rememberPendingSharing(window, context, now);
    const key = [...sessionStorage.values.keys()][0];
    sessionStorage.setItem(key, invalid === 'bad-json' ? '{' : JSON.stringify(invalid));
    assert.equal(pendingSharingURL(window, now), null);
    assert.equal(sessionStorage.values.size, 0);
  }
  assert.equal(rememberPendingSharing({ sessionStorage: storage() }, { ...context, state: 'short' }), false);
});

test('a purchase completed in the same tab can resume its original app connection explicitly', async () => {
  const sessionStorage = storage();
  const original = page(connectionURL, sessionStorage);
  const calls = [];
  await mountSharing(original.document, original.window, async (path) => {
    calls.push(path);
    return Response.json({ paid: false, mode: 'live', recoveryAvailable: true });
  }).ready;
  assert.equal(original.nodes['sharing-connect'].hidden, true);

  // Navigating this tab through the homepage and Stripe leaves same-origin
  // sessionStorage available when Stripe returns to paid confirmation.
  const confirmation = page('/confirmation.html', sessionStorage);
  await mountConfirmation(confirmation.document, confirmation.window, async (path) => {
    calls.push(path);
    return Response.json({ paid: true, mode: 'live' });
  }).ready;
  assert.equal(confirmation.nodes['continue-sharing'].hidden, false);
  assert.equal(confirmation.nodes['continue-sharing'].href, connectionURL);
  assert.deepEqual(calls, ['/api/sharing/status', '/api/status']);
  assert.equal(confirmation.window.location.href, 'https://screencast.to/confirmation.html');

  const resumed = page(confirmation.nodes['continue-sharing'].href, sessionStorage);
  const callback = `to.screencast.app://sharing/callback?code=${'A'.repeat(43)}&state=${context.state}`;
  await mountSharing(resumed.document, resumed.window, async (path) => {
    calls.push(path);
    return path.endsWith('/status')
      ? Response.json({ paid: true, mode: 'live', recoveryAvailable: true })
      : Response.json({ callbackURL: callback });
  }).ready;
  assert.equal(resumed.nodes['sharing-open'].hidden, true);
  assert.equal(calls.includes('/api/sharing/authorize'), false);
  await resumed.nodes['sharing-connect'].dispatch('click');
  assert.equal(resumed.nodes['sharing-open'].href, callback);
  assert.equal(sessionStorage.values.size, 1);
  resumed.nodes['sharing-open'].dispatch('click');
  assert.equal(sessionStorage.values.size, 0);
  assert.equal(calls.some((path) => path.includes('/sign') || path.includes('/upload')), false);
});

test('confirmation never offers connection continuity before verified paid status', async () => {
  for (const status of [202, 403, 503]) {
    const sessionStorage = storage();
    rememberPendingSharing({ sessionStorage }, context);
    const confirmation = page('/confirmation.html', sessionStorage);
    await mountConfirmation(confirmation.document, confirmation.window, async () =>
      Response.json({ paid: false, pending: status === 202, mode: 'live' }, { status })).ready;
    assert.equal(confirmation.nodes['continue-sharing'].hidden, true);
    assert.equal(confirmation.nodes['continue-sharing'].href, undefined);
  }
});

test('missing or expired app context provides a clear cancel-and-reconnect fallback', async () => {
  for (const expired of [false, true]) {
    const sessionStorage = storage();
    if (expired) rememberPendingSharing({ sessionStorage }, context, Date.now() - maxAge - 1);
    const confirmation = page('/confirmation.html', sessionStorage);
    await mountConfirmation(confirmation.document, confirmation.window, async () =>
      Response.json({ paid: true, mode: 'live' })).ready;
    assert.equal(confirmation.nodes['continue-sharing'].hidden, true);
    assert.match(confirmation.nodes['sharing-next-steps'].textContent, /close or cancel any connection window/);
    assert.match(confirmation.nodes['sharing-next-steps'].textContent, /choose Connect purchase/);
  }
});

test('blocked session storage never prevents purchase verification or the normal app connection', async () => {
  const original = page(connectionURL, undefined);
  Object.defineProperty(original.window, 'sessionStorage', { get() { throw new Error('blocked'); } });
  await mountSharing(original.document, original.window, async () =>
    Response.json({ paid: true, mode: 'live', recoveryAvailable: true })).ready;
  assert.equal(original.nodes['sharing-connect'].hidden, false);
  assert.equal(pendingSharingURL(original.window), null);
  assert.doesNotThrow(() => clearPendingSharing(original.window));

  const confirmation = page('/confirmation.html', undefined);
  Object.defineProperty(confirmation.window, 'sessionStorage', { get() { throw new Error('blocked'); } });
  await mountConfirmation(confirmation.document, confirmation.window, async () =>
    Response.json({ paid: true, mode: 'live' })).ready;
  assert.equal(confirmation.nodes.ready.hidden, false);
  assert.equal(confirmation.nodes['continue-sharing'].hidden, true);
  assert.match(confirmation.nodes['sharing-next-steps'].textContent, /close or cancel/);
});

test('failed writes clear a stale request instead of resuming the wrong connection', () => {
  const sessionStorage = storage();
  const window = { sessionStorage };
  rememberPendingSharing(window, context);
  sessionStorage.setItem = () => { throw new Error('quota'); };
  assert.equal(rememberPendingSharing(window, { ...context, state: 'N'.repeat(43) }), false);
  assert.equal(pendingSharingURL(window), null);
});
