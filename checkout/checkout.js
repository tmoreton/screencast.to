export function checkoutPresentation(config) {
  const mode = config?.mode === 'test' || config?.mode === 'live' ? config.mode : null;
  const price = config?.price;
  const validPrice = Number.isSafeInteger(price?.amount) && price.amount > 0 &&
    typeof price.currency === 'string' && /^[a-z]{3}$/i.test(price.currency) &&
    typeof price.formatted === 'string' && price.formatted.length > 0;
  const enabled = config?.enabled === true && config?.downloadReady === true && !!mode && validPrice;
  return {
    enabled, mode, price: validPrice ? price : null,
    button: enabled
      ? (mode === 'test' ? 'Try test checkout' : `Buy Screencast.to — ${price.formatted}`)
      : 'Checkout temporarily unavailable',
    status: enabled
      ? (mode === 'test'
        ? 'Test mode · No real charge. Use Stripe test payment details to verify checkout and delivery.'
        : 'One payment. Secure checkout by Stripe. Your private Mac download follows payment confirmation.')
      : 'Checkout is not available right now. Please check again or contact support@screencast.to.',
  };
}

export function updateDisplayedPrices(document, price) {
  if (!price) return;
  document.querySelectorAll('[data-price]').forEach((node) => { node.textContent = price.formatted; });
  try {
    const formatter = new Intl.NumberFormat('en-US', {
      style: 'currency', currency: price.currency.toUpperCase(),
    });
    const minorDigits = ['isk', 'ugx'].includes(price.currency.toLowerCase())
      ? 2 : formatter.resolvedOptions().maximumFractionDigits;
    const parts = formatter.formatToParts(price.amount / (10 ** minorDigits));
    const currency = parts.find((part) => part.type === 'currency')?.value || price.currency.toUpperCase();
    const number = parts.filter((part) => ['integer', 'group', 'decimal', 'fraction'].includes(part.type))
      .map((part) => part.value).join('');
    document.querySelectorAll('[data-price-currency]').forEach((node) => { node.textContent = currency; });
    document.querySelectorAll('[data-price-number]').forEach((node) => { node.textContent = number; });
  } catch { /* The server-formatted price remains available. */ }
}

export function mountCheckout(document, window, request = window.fetch.bind(window)) {
  const form = document.getElementById('checkout-form');
  const button = document.getElementById('checkout-button');
  const status = document.getElementById('checkout-status');
  const notice = document.getElementById('checkout-notice');
  const retry = document.getElementById('checkout-retry');
  if (!form || !button || !status || !notice || !retry) return;
  const cancelled = new URLSearchParams(window.location.search).get('checkout') === 'cancelled';
  let current = checkoutPresentation(null);
  let loading = false;
  let submitting = false;

  function showNotice(mode) {
    const messages = [];
    if (cancelled) messages.push('Checkout cancelled. Nothing was charged.');
    if (mode === 'test') messages.push('Test checkout is active. No real payments are accepted.');
    notice.textContent = messages.join(' ');
    notice.hidden = messages.length === 0;
    notice.dataset.mode = mode || 'unavailable';
  }

  async function loadAvailability() {
    if (loading) return;
    loading = true;
    submitting = false;
    button.disabled = true;
    button.textContent = 'Checking availability…';
    status.textContent = 'Checking secure checkout and the private Mac release…';
    retry.hidden = true;
    try {
      const response = await request('/api/config', {
        cache: 'no-store', credentials: 'same-origin', signal: AbortSignal.timeout(12000),
      });
      const payload = await response.json();
      current = checkoutPresentation(payload);
      updateDisplayedPrices(document, current.price);
    } catch { current = checkoutPresentation(null); }
    button.disabled = !current.enabled;
    button.textContent = current.button;
    status.textContent = current.status;
    retry.hidden = current.enabled;
    showNotice(current.mode);
    loading = false;
  }

  form.addEventListener('submit', (event) => {
    if (!current.enabled || submitting) {
      event.preventDefault();
      return;
    }
    submitting = true;
    button.disabled = true;
    button.textContent = 'Opening secure checkout…';
  });
  retry.addEventListener('click', loadAvailability);
  loadAvailability();
  return { reload: loadAvailability };
}

if (typeof document !== 'undefined') mountCheckout(document, window);
