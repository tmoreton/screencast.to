const KEY = 'screencast.pending-sharing.v1';
const MAX_AGE = 15 * 60 * 1000;

function validContext(value) {
  return value && typeof value === 'object' && !Array.isArray(value) &&
    typeof value.codeChallenge === 'string' && /^[A-Za-z0-9_-]{43}$/.test(value.codeChallenge) &&
    typeof value.state === 'string' && /^[A-Za-z0-9_-]{32,128}$/.test(value.state);
}

export function clearPendingSharing(window) {
  try { window.sessionStorage.removeItem(KEY); }
  catch { /* Storage can be blocked; connection still works without checkout continuity. */ }
}

export function rememberPendingSharing(window, context, now = Date.now()) {
  if (!validContext(context) || !Number.isSafeInteger(now) || now <= 0) return false;
  try {
    // These public PKCE binding values are the only data retained across checkout.
    window.sessionStorage.setItem(KEY, JSON.stringify({
      codeChallenge: context.codeChallenge, state: context.state, createdAt: now,
    }));
    return true;
  } catch { clearPendingSharing(window); return false; }
}

export function pendingSharingURL(window, now = Date.now()) {
  try {
    const value = JSON.parse(window.sessionStorage.getItem(KEY));
    if (!validContext(value) || Object.keys(value).length !== 3 ||
        !Number.isSafeInteger(value.createdAt) || value.createdAt <= 0 ||
        !Number.isSafeInteger(now) || value.createdAt > now || now - value.createdAt >= MAX_AGE) {
      clearPendingSharing(window);
      return null;
    }
    const query = new URLSearchParams({ code_challenge: value.codeChallenge, state: value.state });
    return `/connect-sharing.html?${query}`;
  } catch {
    clearPendingSharing(window);
    return null;
  }
}
