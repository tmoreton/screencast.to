import { cp, lstat, mkdir, readdir, rm } from 'node:fs/promises';
import { extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const output = new URL('public/', root);
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });

export const publicFiles = [
  'index.html', 'confirmation.html', 'confirmation.js', 'checkout.js',
  'styles.css', 'assets', 'bundle', 'policies', 'support.html', 'robots.txt',
  'sitemap.xml',
];

async function validateDirectory(url) {
  for (const entry of await readdir(url)) {
    const child = new URL(entry, url);
    const info = await lstat(child);
    if (entry.startsWith('.') || info.isSymbolicLink()) throw new Error(`Unexpected public asset: ${entry}`);
    if (info.isDirectory()) await validateDirectory(new URL(`${entry}/`, url));
    else if (!['.html', '.svg', '.png', '.jpg', '.webp'].includes(extname(entry))) {
      throw new Error(`Unexpected public file: ${entry}`);
    }
  }
}

for (const name of publicFiles) {
  const source = new URL(name, root);
  const info = await lstat(source);
  if (info.isSymbolicLink()) throw new Error(`Unexpected public symlink: ${name}`);
  if (info.isDirectory()) await validateDirectory(new URL(`${name}/`, root));
  await cp(source, new URL(name, output), { recursive: true });
}
console.log(`Built public website in ${fileURLToPath(output)}`);
