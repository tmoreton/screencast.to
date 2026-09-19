import { stripeMode } from './stripe.js';

const DEFAULT_MANIFEST_PATH = 'releases/current.json';

export function checkoutSettings(environment = process.env) {
  let baseUrl = null;
  let configuredBase = environment.CHECKOUT_BASE_URL;
  if (!configuredBase && environment.VERCEL_ENV === 'preview' &&
      /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.vercel\.app$/i.test(environment.VERCEL_URL || '')) {
    configuredBase = `https://${environment.VERCEL_URL}`;
  }
  try {
    const candidate = new URL(configuredBase);
    const local = ['development', 'test'].includes(environment.NODE_ENV) &&
      environment.VERCEL_ENV !== 'production' &&
      ['localhost', '127.0.0.1', '[::1]'].includes(candidate.hostname);
    if ((candidate.protocol === 'https:' || (local && candidate.protocol === 'http:')) &&
        candidate.pathname === '/' && !candidate.search && !candidate.hash &&
        !candidate.username && !candidate.password) baseUrl = candidate;
  } catch { /* Invalid or missing origins keep checkout disabled. */ }

  const priceId = /^price_[A-Za-z0-9]+$/.test(environment.STRIPE_PRICE_ID || '')
    ? environment.STRIPE_PRICE_ID : null;
  const manifestPath = environment.RELEASE_MANIFEST_PATH || DEFAULT_MANIFEST_PATH;
  const storageReady = Boolean(environment.BLOB_READ_WRITE_TOKEN?.trim()) &&
    /^releases\/[A-Za-z0-9._-]+\.json$/.test(manifestPath);
  const mode = stripeMode(environment);
  return {
    baseUrl, priceId, mode, manifestPath, storageReady,
    enabled: environment.CHECKOUT_ENABLED === 'true' &&
      Boolean(baseUrl && priceId && mode && storageReady),
  };
}

export async function loadCheckoutPrice(stripe, settings) {
  const price = await stripe.prices.retrieve(settings.priceId, { expand: ['product'] });
  if (price.id !== settings.priceId || !price.active || price.type !== 'one_time' ||
      price.billing_scheme !== 'per_unit' || price.recurring || price.custom_unit_amount ||
      price.transform_quantity || price.livemode !== (settings.mode === 'live') ||
      !Number.isSafeInteger(price.unit_amount) || price.unit_amount <= 0 ||
      !/^[a-z]{3}$/.test(price.currency || '') || !price.product?.active) return null;

  const formatter = new Intl.NumberFormat('en-US', { style: 'currency', currency: price.currency });
  const decimals = ['isk', 'ugx'].includes(price.currency)
    ? 2 : formatter.resolvedOptions().maximumFractionDigits;
  return {
    amount: price.unit_amount,
    currency: price.currency,
    formatted: formatter.format(price.unit_amount / (10 ** decimals)),
  };
}
