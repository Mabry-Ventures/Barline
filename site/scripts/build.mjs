import { cp, mkdir, readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

export const root = fileURLToPath(new URL('../', import.meta.url));
const sourceFiles = ['index.html', 'about/index.html', 'privacy/index.html', '404.html', 'styles.css', '_headers', 'robots.txt'];
const outputFiles = [...sourceFiles, 'assets/barline.png'];

// Refuse stale checkout scripts, symlinks or unrelated assets before uploading.
// Never delete unknown output on the user's behalf.
export async function assertAllowedTree(directory, allowed, prefix = '') {
  let entries;
  try { entries = await readdir(directory, { withFileTypes: true }); }
  catch (error) { if (error.code === 'ENOENT' && !prefix) return; throw error; }
  for (const entry of entries) {
    const path = prefix + entry.name;
    if (entry.isDirectory() && allowed.some(file => file.startsWith(path + '/'))) {
      await assertAllowedTree(join(directory, entry.name), allowed, path + '/');
    } else if (!entry.isFile() || !allowed.includes(path)) {
      throw new Error(`Unexpected static-site entry: ${path}. Review it before building.`);
    }
  }
}

// Static, explicitly staged output. No payment keys, account state, or bundler.
// Publishing is a separate operation after domain/account/release approval.
export async function build() {
  const output = join(root, 'dist');
  await assertAllowedTree(join(root, 'src'), sourceFiles);
  await assertAllowedTree(output, outputFiles);
  for (const file of sourceFiles.filter(file => file.endsWith('.html'))) {
    const html = await readFile(join(root, 'src', file), 'utf8');
    if (/<script\b|<iframe\b|<form\b/i.test(html)) throw new Error('Static site must not embed scripts, checkout, or forms.');
  }
  await mkdir(output, { recursive: true });
  const files = await readdir(join(root, 'src'));
  for (const file of files) {
    await cp(join(root, 'src', file), join(output, file), { recursive: true });
  }
  await mkdir(join(output, 'assets'), { recursive: true });
  await cp(join(root, '../Barline/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png'), join(output, 'assets/barline.png'));
  console.log('Barline staged site built. No deployment or payment activation performed.');
  return output;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await build();
