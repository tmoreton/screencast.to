import { handleUpload } from '@vercel/blob/client';
import { timingSafeEqual } from 'node:crypto';

const VERSION = '[1-9][0-9]{0,3}\\.(?:0|[1-9][0-9]?)\\.(?:0|[1-9][0-9]?)';
const releaseFiles = [
  {
    pattern: new RegExp(`^releases/screencast-${VERSION}\\.dmg$`),
    contentType: 'application/x-apple-diskimage', maximumSizeInBytes: 1024 * 1024 * 1024,
    allowOverwrite: false,
  },
  {
    pattern: new RegExp(`^releases/appcast-${VERSION}\\.xml$`),
    contentType: 'application/xml', maximumSizeInBytes: 2 * 1024 * 1024,
    allowOverwrite: false,
  },
  {
    pattern: /^releases\/current\.json$/,
    contentType: 'application/json', maximumSizeInBytes: 16 * 1024,
    allowOverwrite: true,
  },
];

function privateResponse(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'private, no-store, max-age=0',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

function matchesBearer(request, expected) {
  if (typeof expected !== 'string' || expected.length < 32) return false;
  const authorization = request.headers.get('Authorization') || '';
  if (!authorization.startsWith('Bearer ')) return false;
  const suppliedBytes = Buffer.from(authorization.slice('Bearer '.length));
  const expectedBytes = Buffer.from(expected);
  return suppliedBytes.length === expectedBytes.length &&
    timingSafeEqual(suppliedBytes, expectedBytes);
}

function uploadPolicy(pathname) {
  return releaseFiles.find(({ pattern }) => pattern.test(pathname));
}

export function createReleasePublisher({
  environment = () => process.env,
  uploadHandler = handleUpload,
  logger = console,
} = {}) {
  return async function publish(request) {
    const env = environment();
    if (!matchesBearer(request, env.RELEASE_PUBLISH_TOKEN)) {
      return privateResponse(JSON.stringify({ error: 'Release authorization required.' }), 401);
    }
    if (!env.BLOB_READ_WRITE_TOKEN) {
      return privateResponse(JSON.stringify({ error: 'Release storage is not configured.' }), 503);
    }

    try {
      const body = await request.json();
      if (body?.type !== 'blob.generate-client-token') {
        return privateResponse(JSON.stringify({ error: 'Unsupported release operation.' }), 400);
      }
      const pathname = body?.payload?.pathname;
      const policy = typeof pathname === 'string' ? uploadPolicy(pathname) : null;
      if (!policy) return privateResponse(JSON.stringify({ error: 'Release pathname is not allowed.' }), 400);

      const result = await uploadHandler({
        request,
        body,
        token: env.BLOB_READ_WRITE_TOKEN,
        onBeforeGenerateToken: async () => ({
          allowedContentTypes: [policy.contentType],
          maximumSizeInBytes: policy.maximumSizeInBytes,
          validUntil: Date.now() + 5 * 60 * 1000,
          addRandomSuffix: false,
          allowOverwrite: policy.allowOverwrite,
        }),
      });
      return privateResponse(JSON.stringify(result));
    } catch (error) {
      logger.error('Release upload authorization failed:', error?.name || 'unknown');
      return privateResponse(JSON.stringify({ error: 'Release upload authorization failed.' }), 400);
    }
  };
}

