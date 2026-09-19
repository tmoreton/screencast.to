import { get, issueSignedToken, presignUrl } from '@vercel/blob';

const VERSION = /^[1-9][0-9]{0,3}\.(?:0|[1-9][0-9]?)\.(?:0|[1-9][0-9]?)$/;
const SHA256 = /^[a-f0-9]{64}$/;

export async function loadReleaseManifest(environment = process.env, getBlob = get) {
  const pathname = environment.RELEASE_MANIFEST_PATH || 'releases/current.json';
  if (!/^releases\/[A-Za-z0-9._-]+\.json$/.test(pathname) ||
      !environment.BLOB_READ_WRITE_TOKEN?.trim()) return null;
  const result = await getBlob(pathname, {
    access: 'private', token: environment.BLOB_READ_WRITE_TOKEN,
  });
  if (!result || result.statusCode !== 200 || !result.stream) return null;
  let value;
  try { value = await new Response(result.stream).json(); } catch { return null; }
  if (!value || value.product !== 'screencast-mac' || !VERSION.test(value.version || '') ||
      value.pathname !== `releases/screencast-${value.version}.dmg` ||
      value.appcastPath !== `releases/appcast-${value.version}.xml` ||
      !SHA256.test(value.sha256 || '') ||
      !Number.isSafeInteger(value.size) || value.size <= 0) return null;
  return value;
}

export function hasUpdateAuthorization(request, environment = process.env) {
  const expected = environment.SPARKLE_UPDATE_TOKEN;
  if (typeof expected !== 'string' || expected.length < 32) return false;
  const actual = request.headers.get('Authorization') || '';
  const supplied = actual.startsWith('Bearer ') ? actual.slice(7) : '';
  if (supplied.length !== expected.length) return false;
  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= expected.charCodeAt(index) ^ supplied.charCodeAt(index);
  }
  return difference === 0;
}

export async function signedReleaseUrl(pathname, environment = process.env, now = Date.now,
  signToken = issueSignedToken, signUrl = presignUrl) {
  const validUntil = now() + 5 * 60 * 1000;
  const token = await signToken({
    pathname, operations: ['get'], validUntil, token: environment.BLOB_READ_WRITE_TOKEN,
  });
  const { presignedUrl } = await signUrl(token, {
    pathname, operation: 'get', access: 'private', validUntil,
  });
  const url = new URL(presignedUrl);
  if (url.protocol !== 'https:' || !url.hostname.endsWith('.private.blob.vercel-storage.com') ||
      url.username || url.password || (url.port && url.port !== '443')) {
    throw new Error('Blob returned an invalid private download URL');
  }
  return url;
}
