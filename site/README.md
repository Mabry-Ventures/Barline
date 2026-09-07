# Barline site

Static HTML/CSS for Cloudflare Pages. No framework, client JavaScript, third-party
fonts, analytics, forms, payment SDK, cookies, database, or app backend.

```sh
cd site
npm test
npm run build
npm run preview
```

Output: ignored `site/dist/`. Preview binds only to `127.0.0.1:4178`. No dependency
installation is needed. The icon is copied from the existing native app asset.

## Staging, not publication

The site shows pending release availability and is marked `noindex`. The user
registered `usebarline.com` and authorized staging plus live support setup after
sandbox success/decline/abandonment checks. The support button opens:
https://buy.stripe.com/cNibJ1a370l33AVgnk1ck02
This accepts real payments even from preview; visible copy warns visitors.
No real payment was submitted during live verification.
No card fields, keys, webhooks, entitlement state or app payment logic are needed.

Cloudflare Pages output is `dist`, project root is `site`. The supplied Wrangler
configuration targets the `barline-site` Direct Upload project in Mabry Ventures.
The `staging` branch is a Preview environment, not production. Direct Upload
cannot later switch to Git integration without creating a new Pages project;
select deployment ownership deliberately. Do not add a second GitHub workflow.

Verified preview: https://staging.barline-site.pages.dev
Latest immutable deployment: https://5c0693c2.barline-site.pages.dev
Live-support update: September 7, 2026. Evidence: `QA.md`.
The provider lists source `184edc7`, but this upload includes uncommitted site
changes; that field is not a complete source certificate. Asset hashes and
deployed content checks are retained under ignored `.artifacts/site/`.
No custom domain, production deployment or public app release was activated.
Live checkout is active. `noindex` discourages indexing; it is not access control.

Before public launch: confirm domain/TLS and redirects, qualify real download
and complete source/archive links, remove preview-only real-payment/indexing
wording and restrictions, check external links, verify
deployed security headers/404 and re-run desktop/mobile/keyboard QA. Publishing
the app release/update feed still requires the user's final approval.

## Design system

Two generated section references, retained under ignored `.artifacts/site/design/`,
define the implementation: true white background, graphite text, restrained
cobalt actions, native system sans, open columns and thin rules, 12px buttons.
No card grid, hero eyebrow, animated background, or commercial pricing tiers.

Allowed hero copy: Barline; How it works; Support; Your menu bar, organized.;
Your Mac, uninterrupted.; A quieter menu bar. A native Mac utility.; Everything
stays on your Mac.; Release status; See how it works; For Apple Silicon · macOS 26.

Intentional accuracy deviations: use the real Barline icon, not the generated
approximation; replace the invented two-row Customize Shelf illustration with
a clearly labeled single-row disclosure demonstration; use explicit unqualified
macOS 27 language. The illustration is not a screenshot or a real OS control.
Its generic symbols are native SVG icons; all website text/controls are HTML.
On phones columns stack in reading order and the illustrated shelf stays in bounds.
