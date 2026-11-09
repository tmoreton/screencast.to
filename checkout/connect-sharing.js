const CHALLENGE = /^[A-Za-z0-9_-]{43}$/;
const STATE = /^[A-Za-z0-9_-]{32,128}$/;
const OPAQUE = /^[A-Za-z0-9_-]{32,2048}$/;

export function sharingContext(search) {
  const params = new URLSearchParams(search);
  const keys = ['code_challenge', 'state', 'restore'];
  if ([...params.keys()].some((key) => !keys.includes(key)) ||
      keys.some((key) => params.getAll(key).length > 1)) return null;
  const codeChallenge = params.get('code_challenge');
  const state = params.get('state');
  const restore = params.get('restore');
  if ((codeChallenge !== null || state !== null) &&
      (!CHALLENGE.test(codeChallenge || '') || !STATE.test(state || ''))) return null;
  if (restore !== null && !OPAQUE.test(restore)) return null;
  return { codeChallenge, state, restore };
}

export function sharingCallback(value, expectedState) {
  if (typeof value !== 'string' || !STATE.test(expectedState || '')) return null;
  try {
    const url = new URL(value);
    const params = url.searchParams;
    if (url.protocol !== 'to.screencast.app:' || url.hostname !== 'sharing' ||
        url.pathname !== '/callback' || url.username || url.password || url.port || url.hash ||
        [...params.keys()].some((key) => !['code', 'state'].includes(key)) ||
        params.getAll('code').length !== 1 || params.getAll('state').length !== 1 ||
        !OPAQUE.test(params.get('code') || '') || params.get('state') !== expectedState) return null;
    return url.href;
  } catch { return null; }
}

export function mountSharing(document, window, request = window.fetch.bind(window)) {
  const ids = ['sharing-status', 'sharing-test', 'sharing-connect', 'sharing-open',
    'sharing-recovery', 'sharing-email', 'sharing-send', 'sharing-retry',
    'sharing-download', 'sharing-start-again'];
  const nodes = Object.fromEntries(ids.map((id) => [id, document.getElementById(id)]));
  if (Object.values(nodes).some((node) => !node)) return;
  const status = nodes['sharing-status'];
  const connect = nodes['sharing-connect'];
  const open = nodes['sharing-open'];
  const recovery = nodes['sharing-recovery'];
  const email = nodes['sharing-email'];
  const send = nodes['sharing-send'];
  const retry = nodes['sharing-retry'];
  const context = sharingContext(window.location.search);

  // Consume email credentials once, and remove them before any network request.
  const cleanURL = new URL(window.location.href);
  if (cleanURL.searchParams.has('restore')) {
    cleanURL.searchParams.delete('restore');
    window.history.replaceState(null, '', cleanURL.pathname + cleanURL.search);
  }
  let restore = context?.restore;
  let paid = false;
  let recoveryAvailable = false;
  let busy = false;
  let generation = 0;
  const connecting = Boolean(context?.codeChallenge && context?.state);
  const restart = new URLSearchParams();
  if (connecting) {
    restart.set('code_challenge', context.codeChallenge);
    restart.set('state', context.state);
  }
  nodes['sharing-start-again'].href = `/connect-sharing.html${restart.size ? `?${restart}` : ''}`;

  function resetActions() {
    connect.hidden = true;
    open.hidden = true;
    open.removeAttribute('href');
    recovery.hidden = true;
    retry.hidden = true;
    nodes['sharing-download'].hidden = true;
    nodes['sharing-start-again'].hidden = true;
  }

  function renderPurchase() {
    resetActions();
    send.disabled = false;
    if (paid && connecting) {
      connect.hidden = false;
      connect.disabled = false;
      status.textContent = 'Your website purchase is verified. Connect sharing to this Mac. Recordings upload only when you choose Upload.';
    } else if (paid) {
      nodes['sharing-download'].hidden = false;
      status.textContent = 'Your website purchase is verified. To connect sharing, return to Screencast and choose Connect sharing.';
    } else if (recoveryAvailable) {
      recovery.hidden = false;
      status.textContent = 'Enter the email used at checkout to verify your website purchase. We will send a secure link if an eligible purchase is found.';
    } else {
      retry.hidden = false;
      status.textContent = 'Purchase verification by email is temporarily unavailable. Try again shortly or contact support@screencast.to.';
    }
  }

  async function api(path, body) {
    return request(path, {
      method: body === undefined ? 'GET' : 'POST', credentials: 'same-origin', cache: 'no-store',
      signal: AbortSignal.timeout(12000),
      ...(body === undefined ? {} : {
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      }),
    });
  }

  async function checkPurchase() {
    if (!context || busy) return;
    busy = true;
    const current = ++generation;
    resetActions();
    status.textContent = 'Checking your website purchase…';
    try {
      const response = await api('/api/sharing/status');
      if (!response.ok) throw new Error('unavailable');
      const payload = await response.json();
      if (current !== generation) return;
      if (typeof payload?.paid !== 'boolean' ||
          (payload.paid && !['live', 'test'].includes(payload.mode))) throw new Error('invalid status');
      paid = payload.paid;
      recoveryAvailable = payload.recoveryAvailable === true;
      nodes['sharing-test'].hidden = payload.mode !== 'test';
      renderPurchase();
    } catch {
      if (current !== generation) return;
      paid = false;
      retry.hidden = false;
      status.textContent = 'We could not check your purchase right now. Please try again.';
    } finally { if (current === generation) busy = false; }
  }

  async function authorize() {
    if (!context || !connecting || !paid || busy) return;
    busy = true;
    const current = ++generation;
    connect.disabled = true;
    status.textContent = 'Preparing a secure connection to Screencast…';
    try {
      const response = await api('/api/sharing/authorize', {
        codeChallenge: context.codeChallenge, state: context.state,
      });
      if (!response.ok) throw new Error('unavailable');
      const payload = await response.json();
      const callback = sharingCallback(payload?.callbackURL, context.state);
      if (current !== generation) return;
      if (!callback) throw new Error('invalid callback');
      open.href = callback;
      open.hidden = false;
      connect.hidden = true;
      status.textContent = 'Ready to return to Screencast. Open the app to finish connecting. Nothing has been uploaded.';
    } catch {
      if (current !== generation) return;
      connect.disabled = false;
      status.textContent = 'We could not connect sharing right now. Try Connect sharing again, or reopen this page from the app.';
    } finally { if (current === generation) busy = false; }
  }

  async function sendRecovery(event) {
    event.preventDefault();
    if (!context || !recoveryAvailable || busy || !recovery.reportValidity()) return;
    const address = email.value.trim();
    if (!address || address.length > 254) return;
    busy = true;
    const current = ++generation;
    send.disabled = true;
    status.textContent = 'Requesting a secure purchase email…';
    try {
      const response = await api('/api/sharing/restore', {
        email: address,
        ...(connecting ? { codeChallenge: context.codeChallenge, state: context.state } : {}),
      });
      if (current !== generation) return;
      if (response.status === 429) {
        status.textContent = 'Please wait a few minutes before requesting another purchase email.';
      } else if (!response.ok) {
        status.textContent = 'Purchase email is temporarily unavailable. Please try again shortly or contact support@screencast.to.';
      } else {
        const payload = await response.json();
        if (current !== generation) return;
        if (payload?.sent !== true) throw new Error('invalid response');
        email.value = '';
        status.textContent = 'If an eligible purchase uses that address, a verification link is on its way. Check your inbox and spam folder.';
      }
    } catch {
      if (current !== generation) return;
      status.textContent = 'We could not request your purchase email. Please try again.';
    } finally {
      if (current === generation) { busy = false; send.disabled = false; }
    }
  }

  async function initialize() {
    resetActions();
    if (!context) {
      nodes['sharing-start-again'].hidden = false;
      status.textContent = 'This connection or purchase link is invalid. Return to Screencast and choose Connect sharing, or start a new purchase recovery.';
      return;
    }
    if (restore) {
      const token = restore;
      restore = null;
      busy = true;
      const current = ++generation;
      let restored = false;
      status.textContent = 'Verifying your secure purchase link…';
      try {
        const response = await api('/api/sharing/restore/complete', { token });
        restored = response.ok && (await response.json())?.paid === true;
      } catch { /* An expired or unavailable link can be replaced without exposing its token. */ }
      if (current !== generation) return;
      busy = false;
      await checkPurchase();
      if (!restored) {
        nodes['sharing-start-again'].hidden = false;
        status.textContent = 'This purchase link has expired, was already used, or could not be verified. Request a new email to try again.';
      }
      return;
    }
    await checkPurchase();
  }

  connect.addEventListener('click', authorize);
  recovery.addEventListener('submit', sendRecovery);
  retry.addEventListener('click', checkPurchase);
  window.addEventListener('pagehide', () => { generation += 1; busy = false; });
  window.addEventListener('pageshow', (event) => {
    if (event.persisted) return checkPurchase();
  });
  const ready = initialize();
  return { ready, reload: checkPurchase };
}

if (typeof document !== 'undefined') mountSharing(document, window);
