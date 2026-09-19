import { get } from '@vercel/blob';
import { allowedPriceIds, checkoutProductMarker, isPaidMacPurchase, loadMacPurchase, loadPaidMacPurchase, privateResponse } from './purchase.js';
import { purchaseCookieHeader, requestedPurchaseSessionId } from './purchase-identity.js';
import { hasUpdateAuthorization, loadReleaseManifest, signedReleaseUrl } from './releases.js';
import { checkoutSettings, loadCheckoutPrice } from './settings.js';
import { stripeClient } from './stripe.js';

function json(body, status = 200, headers = {}) {
  return privateResponse(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json; charset=utf-8', ...headers },
  });
}

export function createHandlers({
  environment = () => process.env,
  stripeFactory = stripeClient,
  getBlob = get,
  loadManifest = loadReleaseManifest,
  signRelease = signedReleaseUrl,
  logger = console,
} = {}) {
  const report = (message, error) => logger.error(message, error?.type || error?.name || 'unknown');

  async function currentRelease(env) {
    return loadManifest(env, getBlob);
  }

  return {
    async config() {
      const env = environment();
      const settings = checkoutSettings(env);
      const body = { enabled: false, mode: settings.mode, price: null, downloadReady: false };
      if (!settings.mode || !settings.priceId || !settings.storageReady) return json(body);
      try {
        const [price, release] = await Promise.all([
          loadCheckoutPrice(stripeFactory(env), settings), currentRelease(env),
        ]);
        body.price = price;
        body.downloadReady = Boolean(release);
        body.enabled = settings.enabled && Boolean(price && release);
        return json(body);
      } catch (error) {
        report('Checkout configuration check failed:', error);
        return json(body, 503);
      }
    },

    async checkout(request) {
      const env = environment();
      const settings = checkoutSettings(env);
      if (!settings.enabled) return privateResponse('Checkout is not ready.', { status: 503 });
      const origin = request?.headers.get('Origin');
      const fetchSite = request?.headers.get('Sec-Fetch-Site');
      if ((origin && origin !== settings.baseUrl.origin) ||
          (fetchSite && !['same-origin', 'none'].includes(fetchSite))) {
        return privateResponse('Cross-site checkout is not allowed.', { status: 403 });
      }
      try {
        const stripe = stripeFactory(env);
        const [price, release] = await Promise.all([
          loadCheckoutPrice(stripe, settings), currentRelease(env),
        ]);
        if (!price || !release) return privateResponse('Checkout is not ready.', { status: 503 });
        const session = await stripe.checkout.sessions.create({
          mode: 'payment',
          line_items: [{ price: settings.priceId, quantity: 1 }],
          customer_creation: 'always',
          success_url: new URL('/api/complete?session_id={CHECKOUT_SESSION_ID}', settings.baseUrl).href,
          cancel_url: new URL('/?checkout=cancelled', settings.baseUrl).href,
          metadata: { product: checkoutProductMarker() },
        });
        const url = new URL(session.url);
        if (url.protocol !== 'https:' || url.hostname !== 'checkout.stripe.com' ||
            url.username || url.password || (url.port && url.port !== '443')) {
          throw new Error('Stripe returned an invalid checkout URL');
        }
        return privateResponse(null, { status: 303, headers: { Location: url.href } });
      } catch (error) {
        report('Checkout session creation failed:', error);
        return privateResponse('Checkout is temporarily unavailable.', { status: 502 });
      }
    },

    async complete(request) {
      const env = environment();
      const { mode } = checkoutSettings(env);
      if (!mode) return privateResponse('Purchase confirmation is not ready.', { status: 503 });
      if (!new URL(request.url).searchParams.has('session_id')) {
        return privateResponse('Purchase link could not be verified.', { status: 403 });
      }
      const sessionId = requestedPurchaseSessionId(request, mode, env);
      const cookie = purchaseCookieHeader(request, sessionId, mode, env);
      if (!cookie) return privateResponse('Purchase link could not be verified.', { status: 403 });
      return privateResponse(null, {
        status: 303, headers: { Location: '/confirmation.html', 'Set-Cookie': cookie },
      });
    },

    async status(request) {
      const env = environment();
      const { mode } = checkoutSettings(env);
      const denied = { paid: false, pending: false, mode };
      if (!mode || allowedPriceIds(env).size === 0) return json(denied, 503);
      try {
        const prices = allowedPriceIds(env);
        const sessionId = requestedPurchaseSessionId(request, mode, env);
        const session = await loadMacPurchase(stripeFactory(env), sessionId, prices, mode);
        if (isPaidMacPurchase(session, prices)) return json({ paid: true, pending: false, mode });
        if (session && (session.status === 'open' ||
            (session.status === 'complete' && session.payment_status === 'unpaid'))) {
          return json({ paid: false, pending: true, mode }, 202);
        }
        return json(denied, 403);
      } catch (error) {
        report('Purchase status check failed:', error);
        return json(denied, 502);
      }
    },

    async download(request) {
      const env = environment();
      const { mode, storageReady } = checkoutSettings(env);
      if (!mode || !storageReady || allowedPriceIds(env).size === 0) {
        return privateResponse('The download is not ready.', { status: 503 });
      }
      try {
        const sessionId = requestedPurchaseSessionId(request, mode, env);
        const [session, release] = await Promise.all([
          loadPaidMacPurchase(stripeFactory(env), sessionId, allowedPriceIds(env), mode),
          currentRelease(env),
        ]);
        if (!session) return privateResponse('Purchase could not be verified.', { status: 403 });
        if (!release) return privateResponse('The download is not ready.', { status: 503 });
        const url = await signRelease(release.pathname, env);
        return privateResponse(null, { status: 303, headers: { Location: url.href } });
      } catch (error) {
        report('Private download failed:', error);
        return privateResponse('The download is temporarily unavailable.', { status: 502 });
      }
    },

    async appcast(request) {
      const env = environment();
      if (!hasUpdateAuthorization(request, env)) {
        return privateResponse('Update authorization required.', { status: 401 });
      }
      try {
        const release = await currentRelease(env);
        if (!release) return privateResponse('No update feed is available.', { status: 404 });
        const result = await getBlob(release.appcastPath, {
          access: 'private', token: env.BLOB_READ_WRITE_TOKEN,
        });
        if (!result || result.statusCode !== 200 || !result.stream) {
          return privateResponse('No update feed is available.', { status: 404 });
        }
        return privateResponse(result.stream, {
          status: 200,
          headers: { 'Content-Type': 'application/xml; charset=utf-8' },
        });
      } catch (error) {
        report('Private appcast failed:', error);
        return privateResponse('The update feed is temporarily unavailable.', { status: 502 });
      }
    },

    async update(request) {
      const env = environment();
      if (!hasUpdateAuthorization(request, env)) {
        return privateResponse('Update authorization required.', { status: 401 });
      }
      try {
        const release = await currentRelease(env);
        const requestedFile = new URL(request.url).searchParams.get('file');
        if (!release || requestedFile !== release.pathname.slice('releases/'.length)) {
          return privateResponse('Update not found.', { status: 404 });
        }
        const url = await signRelease(release.pathname, env);
        return privateResponse(null, { status: 303, headers: { Location: url.href } });
      } catch (error) {
        report('Private update failed:', error);
        return privateResponse('The update is temporarily unavailable.', { status: 502 });
      }
    },
  };
}
