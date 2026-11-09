import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { mountSharing, sharingCallback, sharingContext } from '../connect-sharing.js';

const challenge = 'C'.repeat(43);
const state = 'S'.repeat(43);
const token = 'T'.repeat(600);
const query = `?code_challenge=${challenge}&state=${state}`;
const callback = `to.screencast.app://sharing/callback?code=${token}&state=${state}`;

function harness(search, respond) {
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
  const ids = ['sharing-status', 'sharing-test', 'sharing-connect', 'sharing-open',
    'sharing-recovery', 'sharing-email', 'sharing-send', 'sharing-retry',
    'sharing-download', 'sharing-start-again'];
  const nodes = Object.fromEntries(ids.map((id) => [id, target()]));
  const calls = [];
  const trace = [];
  const window = {
    ...target(), location: { href: `https://screencast.to/connect-sharing.html${search}`, search },
    history: {
      replaceState(_state, _title, url) {
        trace.push('strip-token');
        const clean = new URL(url, 'https://screencast.to');
        window.location.href = clean.href;
        window.location.search = clean.search;
      },
    },
  };
  const document = { getElementById: (id) => nodes[id] };
  const sharing = mountSharing(document, window, (path, options) => {
    const call = { path, ...options, body: options.body ? JSON.parse(options.body) : undefined };
    calls.push(call);
    trace.push(path);
    return Promise.resolve(respond(call));
  });
  return { nodes, window, calls, trace, sharing };
}

const verified = () => Response.json({ paid: true, mode: 'live', recoveryAvailable: true });
const unverified = () => Response.json({ paid: false, mode: 'live', recoveryAvailable: true });

test('sharing links require complete, unique app context and bounded opaque tokens', () => {
  assert.deepEqual(sharingContext(query), { codeChallenge: challenge, state, restore: null });
  assert.deepEqual(sharingContext(''), { codeChallenge: null, state: null, restore: null });
  assert.equal(sharingContext(`${query}&restore=${token}`).restore, token);
  for (const search of [
    `?state=${state}`, `?code_challenge=${challenge}`, `${query}&state=${state}`,
    `${query}&code_challenge=${challenge}`, `${query}&restore=${token}&restore=${token}`,
    `${query}&restore=short`, `${query}&restore=${'T'.repeat(2049)}`,
    `${query}&unexpected=true`, `?code_challenge=${'C'.repeat(42)}&state=${state}`,
  ]) assert.equal(sharingContext(search), null);
});

test('only the exact native callback with a matching state can become an app link', () => {
  assert.equal(sharingCallback(callback, state), callback);
  for (const value of [
    `https://sharing/callback?code=${token}&state=${state}`,
    `javascript:alert(1)`, callback.replace('://sharing/', '://evil.example/'),
    callback.replace('://sharing/', '://user@sharing/'),
    callback.replace('://sharing/', '://sharing:443/'),
    callback.replace('/callback?', '/other?'), `${callback}#fragment`,
    `${callback}&state=${state}`, `${callback}&code=${token}`, `${callback}&redirect=https://evil.example`,
    callback.replace(`state=${state}`, `state=${'E'.repeat(43)}`),
  ]) assert.equal(sharingCallback(value, state), null);
});

test('verified purchasers explicitly connect, then explicitly open the app without uploading', async () => {
  const h = harness(query, ({ path }) => path.endsWith('/status')
    ? verified() : Response.json({ callbackURL: callback }));
  await h.sharing.ready;
  assert.equal(h.nodes['sharing-connect'].hidden, false);
  assert.equal(h.nodes['sharing-open'].hidden, true);
  assert.deepEqual(h.calls.map(({ path }) => path), ['/api/sharing/status']);
  await h.nodes['sharing-connect'].dispatch('click');
  assert.deepEqual(h.calls[1].body, { codeChallenge: challenge, state });
  assert.equal(h.calls[1].method, 'POST');
  assert.equal(h.calls[1].credentials, 'same-origin');
  assert.equal(h.nodes['sharing-open'].href, callback);
  assert.equal(h.nodes['sharing-open'].hidden, false);
  assert.equal(h.window.location.href, `https://screencast.to/connect-sharing.html${query}`);
  assert.match(h.nodes['sharing-status'].textContent, /Nothing has been uploaded/);
  assert.deepEqual(h.calls.map(({ path }) => path), ['/api/sharing/status', '/api/sharing/authorize']);
});

test('an unsafe callback or authorization failure never opens an app and permits retry', async () => {
  let attempts = 0;
  const h = harness(query, ({ path }) => {
    if (path.endsWith('/status')) return verified();
    attempts += 1;
    return attempts === 1 ? Response.json({ callbackURL: 'https://evil.example/' }) : new Response('', { status: 503 });
  });
  await h.sharing.ready;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    await h.nodes['sharing-connect'].dispatch('click');
    assert.equal(h.nodes['sharing-open'].hidden, true);
    assert.equal(h.nodes['sharing-open'].href, undefined);
    assert.equal(h.nodes['sharing-connect'].disabled, false);
    assert.match(h.nodes['sharing-status'].textContent, /could not connect sharing/);
  }
});

test('invalid or duplicated query context makes no API calls or credential form available', async () => {
  for (const search of [`?state=${state}`, `${query}&state=${state}`, `${query}&restore=short`]) {
    const h = harness(search, () => { throw new Error('must not request'); });
    await h.sharing.ready;
    assert.equal(h.calls.length, 0);
    assert.equal(h.nodes['sharing-recovery'].hidden, true);
    assert.equal(h.nodes['sharing-connect'].hidden, true);
    assert.match(h.nodes['sharing-status'].textContent, /invalid/);
    assert.equal(h.window.location.search.includes('restore='), false);
  }
});

test('email recovery carries validated app context and gives a neutral, retryable response', async () => {
  const h = harness(query, ({ path }) => path.endsWith('/status')
    ? unverified() : Response.json({ sent: true }));
  await h.sharing.ready;
  h.nodes['sharing-email'].value = 'buyer@example.test';
  const event = new Event('submit', { cancelable: true });
  await h.nodes['sharing-recovery'].dispatch('submit', event);
  assert.equal(event.defaultPrevented, true);
  assert.deepEqual(h.calls[1].body, { email: 'buyer@example.test', codeChallenge: challenge, state });
  assert.equal(h.nodes['sharing-email'].value, '');
  assert.equal(h.nodes['sharing-send'].disabled, false);
  assert.match(h.nodes['sharing-status'].textContent, /If an eligible purchase uses that address/);
});

test('standalone recovery omits app credentials and handles rate limits and outages', async () => {
  for (const status of [429, 503]) {
    const h = harness('', ({ path }) => path.endsWith('/status')
      ? unverified() : new Response('', { status }));
    await h.sharing.ready;
    h.nodes['sharing-email'].value = 'buyer@example.test';
    await h.nodes['sharing-recovery'].dispatch('submit', new Event('submit', { cancelable: true }));
    assert.deepEqual(h.calls[1].body, { email: 'buyer@example.test' });
    assert.equal(h.nodes['sharing-send'].disabled, false);
    assert.match(h.nodes['sharing-status'].textContent, status === 429 ? /wait a few minutes/ : /temporarily unavailable/);
  }
});

test('Back during an email request restores usable controls and ignores the stale result', async () => {
  let finishEmail;
  const h = harness('', ({ path }) => path.endsWith('/status') ? unverified() :
    new Promise((resolve) => { finishEmail = resolve; }));
  await h.sharing.ready;
  h.nodes['sharing-email'].value = 'buyer@example.test';
  const pending = h.nodes['sharing-recovery'].dispatch('submit', new Event('submit', { cancelable: true }));
  assert.equal(h.nodes['sharing-send'].disabled, true);
  h.window.dispatch('pagehide');
  await h.window.dispatch('pageshow', { persisted: true });
  assert.equal(h.nodes['sharing-send'].disabled, false);
  finishEmail(Response.json({ sent: true }));
  await pending;
  assert.match(h.nodes['sharing-status'].textContent, /Enter the email used at checkout/);
});

test('restore tokens leave browser history before use and are never replayed on Back', async () => {
  const h = harness(`?restore=${token}`, ({ path }) => path.endsWith('/complete')
    ? Response.json({ paid: true }) : verified());
  await h.sharing.ready;
  assert.equal(h.trace[0], 'strip-token');
  assert.deepEqual(h.calls[0].body, { token });
  assert.equal(h.window.location.search, '');
  assert.equal(h.nodes['sharing-download'].hidden, false);
  assert.equal(h.nodes['sharing-connect'].hidden, true);
  h.window.dispatch('pagehide');
  await h.window.dispatch('pageshow', { persisted: true });
  assert.deepEqual(h.calls.map(({ path }) => path), [
    '/api/sharing/restore/complete', '/api/sharing/status', '/api/sharing/status',
  ]);
  assert.equal(h.nodes['sharing-status'].textContent.includes(token), false);
});

test('expired single-use links offer fresh email recovery without retaining their token', async () => {
  const h = harness(`${query}&restore=${token}`, ({ path }) => path.endsWith('/complete')
    ? new Response('', { status: 410 }) : unverified());
  await h.sharing.ready;
  assert.match(h.nodes['sharing-status'].textContent, /expired, was already used/);
  assert.equal(h.nodes['sharing-recovery'].hidden, false);
  assert.equal(h.nodes['sharing-start-again'].hidden, false);
  assert.equal(h.nodes['sharing-start-again'].href, `/connect-sharing.html${query}`);
  assert.equal(h.window.location.href.includes(token), false);
});

test('purchase checks fail closed and can be retried without a new recovery token', async () => {
  let attempts = 0;
  const h = harness(query, () => ++attempts === 1 ? new Response('', { status: 503 }) : verified());
  await h.sharing.ready;
  assert.equal(h.nodes['sharing-connect'].hidden, true);
  assert.equal(h.nodes['sharing-retry'].hidden, false);
  await h.nodes['sharing-retry'].dispatch('click');
  assert.equal(h.nodes['sharing-connect'].hidden, false);
});

test('connection page is private, uses external scripts, and describes explicit uploads', async () => {
  const html = await readFile(new URL('../connect-sharing.html', import.meta.url), 'utf8');
  assert.match(html, /name="robots" content="noindex,nofollow"/);
  assert.match(html, /name="referrer" content="no-referrer"/);
  assert.match(html, /script-src 'self'/);
  assert.match(html, /<script type="module" src="\/connect-sharing.js"><\/script>/);
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)/);
  assert.match(html, /explicitly choose Upload/);
  assert.match(html, /type="email"[^>]*required/);
});
