import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, stat, mkdtemp, writeFile, symlink, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { build, assertAllowedTree } from '../scripts/build.mjs';

const output = await build();
const pages = ['index.html', 'about/index.html', 'privacy/index.html', '404.html'];
test('build refuses unexpected stale files and symlinks without deleting them', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'barline-site-manifest-'));
  try {
    await writeFile(join(fixture, 'old-checkout.js'), 'stale');
    await assert.rejects(assertAllowedTree(fixture, ['index.html']), /Unexpected/);
    assert.equal(await readFile(join(fixture, 'old-checkout.js'), 'utf8'), 'stale');
    await symlink('old-checkout.js', join(fixture, 'index.html'));
    await assert.rejects(assertAllowedTree(fixture, ['index.html', 'old-checkout.js']), /Unexpected/);
  } finally { await rm(fixture, { recursive: true }); }
});
test('staged pages have semantic headings, viewport and no tracking/payment code', async () => {
  for (const path of pages) {
    const html = await readFile(join(output, path), 'utf8');
    assert.match(html, /<html lang="en">/);
    assert.match(html, /name="viewport"/);
    assert.equal((html.match(/<h1\b/g) ?? []).length, 1);
    assert.doesNotMatch(html, /<script\b|<iframe\b|<form\b|on(?:click|load|error)=/i);
    assert.match(html, /name="robots" content="noindex/);
  }
});
test('every local link and asset resolves, every local fragment exists', async () => {
  for (const path of pages) {
    const html = await readFile(join(output, path), 'utf8');
    for (const [, raw] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
      const url = new URL(raw, `https://barline.invalid/${path}`);
      if (url.origin !== 'https://barline.invalid') {
        assert.equal(url.protocol, 'https:');
        continue;
      }
      const target = join(output, url.pathname, url.pathname.endsWith('/') ? 'index.html' : '');
      assert.ok((await stat(target)).isFile(), raw);
      if (url.hash) assert.ok((await readFile(target, 'utf8')).includes(`id="${url.hash.slice(1)}"`), raw);
    }
  }
});
test('preview separates live contributions from unqualified downloads and OS claims', async () => {
  const html = await readFile(join(output, 'index.html'), 'utf8');
  assert.match(html, /Checkout accepts real payments, even on this preview site\./);
  assert.match(html, /Downloads will appear here after final qualification\./);
  assert.match(html, /macOS 27 compatibility has not yet been qualified\./);
  assert.doesNotMatch(html, /download="/);
});
test('contributions use only the approved live hosted link with accurate privacy copy', async () => {
  const html = await readFile(join(output, 'index.html'), 'utf8');
  const privacy = await readFile(join(output, 'privacy/index.html'), 'utf8');
  const checkoutLinks = [...html.matchAll(/href="(https:\/\/(?:buy|checkout)\.stripe\.com\/[^\"]+)"/g)].map(match => match[1]);
  assert.deepEqual(checkoutLinks, ['https://buy.stripe.com/cNibJ1a370l33AVgnk1ck02']);
  assert.match(html, /rel="noreferrer">Contribute via Stripe/);
  assert.match(html, /One-time support for Mabry Ventures LLC/);
  assert.match(privacy, /can access transaction details through Stripe/);
  assert.match(privacy, /do not collect full card numbers or security codes/);
  assert.match(privacy, /https:\/\/stripe.com\/privacy/);
  for (const path of pages) {
    const page = await readFile(join(output, path), 'utf8');
    assert.doesNotMatch(page, /buy\.stripe\.com\/test_|sk_(?:live|test)_|pk_(?:live|test)_/);
  }
});
test('static security policy disallows executable/embed/payment surfaces', async () => {
  const headers = await readFile(join(output, '_headers'), 'utf8');
  for (const value of ["default-src 'none'", "frame-ancestors 'none'", "form-action 'none'", 'no-referrer', 'nosniff', 'noindex']) assert.ok(headers.includes(value));
});
test('About preserves provenance while the footer stays focused on navigation', async () => {
  const home = await readFile(join(output, 'index.html'), 'utf8');
  const about = await readFile(join(output, 'about/index.html'), 'utf8');
  assert.match(home, /href="\/about\/"/);
  assert.doesNotMatch(home.match(/<footer[\s\S]*<\/footer>/)[0], /Ice|Derived from/);
  for (const credit of ['Jordan Baird', 'Xinyan Lu', 'Ice', 'GNU General Public License', 'THIRD_PARTY_NOTICES.md', 'PROVENANCE.md']) assert.ok(about.includes(credit));
});
test('site remains lightweight without a client-side framework', async () => {
  const files = [...pages, 'styles.css', 'assets/barline.png'];
  let bytes = 0;
  for (const path of files) bytes += (await stat(join(output, path))).size;
  assert.ok(bytes < 100_000, `Static payload budget exceeded: ${bytes}`);
});
