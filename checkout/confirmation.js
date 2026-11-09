import { pendingSharingURL } from './sharing-pending.js';

export function isValidSessionId(value) {
  return /^cs_(?:test|live)_[A-Za-z0-9]{10,}$/.test(value || '');
}

export function purchasePresentation(payload, httpStatus) {
  const test = payload?.mode === 'test';
  if (httpStatus === 200 && payload?.paid === true) {
    return {
      state: 'ready', test,
      message: test
        ? 'Test payment confirmed. Your Mac download is ready; no real charge was made.'
        : 'Payment confirmed. Your private Mac download is ready.',
    };
  }
  if (httpStatus === 202 && payload?.pending === true) {
    return { state: 'pending', test, message: 'Your payment is still being confirmed. We will check again shortly.' };
  }
  if ([400, 403, 404].includes(httpStatus)) {
    return { state: 'invalid', test, message: 'We could not confirm this purchase. Return using the completed checkout or contact support.' };
  }
  return { state: 'error', test, message: 'We could not check your payment right now. Please try again.' };
}

export function mountConfirmation(document, window, request = window.fetch.bind(window)) {
  const status = document.getElementById('status');
  const ready = document.getElementById('ready');
  const help = document.getElementById('help');
  const download = document.getElementById('download');
  const retry = document.getElementById('retry');
  const testBadge = document.getElementById('test-badge');
  const continueSharing = document.getElementById('continue-sharing');
  const sharingNextSteps = document.getElementById('sharing-next-steps');
  const sessionId = new URLSearchParams(window.location.search).get('session_id');
  const valid = sessionId === null || isValidSessionId(sessionId);
  const sessionQuery = sessionId === null ? '' : `?session_id=${encodeURIComponent(sessionId)}`;
  let attempts = 0;
  let timer;
  let checking = false;
  let disposed = false;
  testBadge.hidden = !valid || !sessionId?.startsWith('cs_test_');

  async function checkPurchase() {
    if (checking || disposed) return;
    window.clearTimeout(timer);
    ready.hidden = true;
    retry.hidden = true;
    help.hidden = true;
    download.removeAttribute('href');
    if (continueSharing) {
      continueSharing.hidden = true;
      continueSharing.removeAttribute('href');
    }
    if (!valid) {
      status.textContent = 'No valid checkout session was found. Return here from a completed checkout.';
      help.hidden = false;
      return;
    }
    checking = true;
    status.textContent = 'Checking your payment with Stripe…';
    try {
      const response = await request(`/api/status${sessionQuery}`, {
        cache: 'no-store', credentials: 'same-origin', signal: AbortSignal.timeout(12000),
      });
      const payload = await response.json();
      const result = purchasePresentation(payload, response.status);
      if (disposed) return;
      status.textContent = result.message;
      testBadge.hidden = !result.test;
      if (result.state === 'ready') {
        download.href = `/api/download${sessionQuery}`;
        ready.hidden = false;
        const connectionURL = pendingSharingURL(window);
        if (continueSharing && connectionURL) {
          continueSharing.href = connectionURL;
          continueSharing.hidden = false;
        }
        if (sharingNextSteps) {
          sharingNextSteps.textContent = connectionURL
            ? 'Your purchase is verified. Continue connecting to finish the original sharing request. Recordings upload only when you choose Upload.'
            : 'For optional cloud sharing, close or cancel any connection window that is still open, then choose Connect purchase in Screencast to start again. Connecting never uploads a recording.';
        }
      } else if (result.state === 'pending' && ++attempts < 6) {
        timer = window.setTimeout(checkPurchase, Math.min(2000 * attempts, 8000));
      } else {
        help.hidden = false;
        retry.hidden = result.state === 'invalid';
        if (result.state === 'pending') {
          status.textContent = 'Payment confirmation is taking longer than expected. Check again shortly or contact support.';
        }
      }
    } catch {
      if (!disposed) {
        status.textContent = 'We could not check your payment right now. Please try again.';
        help.hidden = false;
        retry.hidden = false;
      }
    } finally { checking = false; }
  }

  retry.addEventListener('click', () => { attempts = 0; checkPurchase(); });
  window.addEventListener('pagehide', () => { disposed = true; window.clearTimeout(timer); });
  window.addEventListener('pageshow', (event) => {
    if (event.persisted) { disposed = false; checkPurchase(); }
  });
  const loaded = checkPurchase();
  return { ready: loaded, retry: checkPurchase };
}

if (typeof document !== 'undefined') mountConfirmation(document, window);
