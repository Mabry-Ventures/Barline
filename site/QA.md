# Staged website QA — September 7, 2026

Scope: static preview, not approval to publish the app or advertise macOS 27.
The frontend skill shaped a dependency-free HTML/CSS implementation and required
generated section references followed by real browser comparison.

## Visual comparison ledger

| Point | Reference and implementation check | Disposition |
| --- | --- | --- |
| Composition | White surface, left-aligned two-line hero, two actions, menu illustration, open feature columns | Preserved; no card grid or extra hero copy |
| Type | Native system sans, graphite first line, muted second line, restrained cobalt actions | Preserved hierarchy; native font metrics intentionally differ from raster reference |
| Spacing | Wide desktop gutters and thin section rules; mobile reading order stacks | Checked at 1440, 1505 and 390 px widths without horizontal overflow; container caps at 1296 px |
| Illustration | Reference suggested a two-row Customize Shelf menu | Intentionally replaced with a labeled, generic one-row disclosure; not represented as a product screenshot |
| Accuracy and identity | Approved tagline, real app icon, quiet support section, explicit availability | Real icon replaces generated approximation; macOS 27 is explicitly unqualified |

Above-fold copy matches the allowed copy inventory in README. A mobile line-break
spacing issue was corrected and rechecked. No download, payment, pricing tier,
Focus-mode catalog, or benchmark claim was invented.

Native-size reference comparisons: top 1505×1045 and bottom 1435×1096 against
viewport captures of those sizes. Mobile checked at 390×844. The final deployed
desktop viewport is 1280×720. Screenshots are under `.artifacts/site/`; generated
references are under `.artifacts/site/design/`. The browser's stitched full-page
captures duplicated lower content, so `desktop-full.png` and `mobile-full.png`
are not accepted visual evidence; viewport captures and DOM were used instead.
The later saved `deployed-desktop.png` also captured a blank compositor frame
and is rejected; successful deployed viewport renders are retained in the
browser tool transcript. Do not treat a blank capture as rendered page content.

## Functional and delivery evidence

- Six Node tests pass: semantic pages, resolved local links/fragments, honest
  availability, strict headers, <100 KB static payload, and rejection of stale
  files/symlinks before build without deleting them.
- Browser: disclosure toggles with Enter and Space; release anchor navigates;
  Privacy and Back to Barline links work; local browser warning/error log empty.
- Deployment verified as Preview / staging in Cloudflare. HTTPS home is 200,
  missing page is 404, robots disallows indexing, and CSP/no-referrer/nosniff/
  frame-denial/noindex headers are present. Home and privacy response SHA-256
  match the built assets exactly.
- First browser navigation immediately after deploy returned Cloudflare 522.
  That failed screenshot is retained. Subsequent immutable and staging browser
  loads succeeded; this is a bounded smoke check, not an availability guarantee.
- GitHub source repository is public and Issues enabled. No app files were
  uploaded, and the production custom domain is not connected.

Pending: hosted test checkout qualification,
approved live support URL, qualified public app artifact/source destinations,
production domain/TLS/redirect activation and final production browser check.
Do not remove the noindex controls until the launch gate is approved.

## About and support follow-up — 21:07 UTC

- Seven site tests now pass, including About provenance and footer removal.
- Deployment: https://31862687.barline-site.pages.dev (staging alias updated).
- Home, About and privacy: HTTP 200 and exact local/deployed byte match; missing
  route: 404. About retains security/noindex headers. About SHA-256:
  `5ee300a4bfc7b7546095ce542d2882a3a1a4ecb8636045715b9ab5e09ca520cc`.
- About desktop and 390×844 renders inspected. Mobile document width is 390px;
  no horizontal overflow. Temporary viewport override reset.
- Stripe account confirmed, sandbox validates $1/$500 boundaries. Completed
  payment/decline/cancel proof pending. No live checkout on the deployed site.
- GitHub support notifications and Linear issue intake positively verified;
  remaining consent boundary and receipts: `docs/SUPPORT_DELIVERY.md`.

## Live support staging — September 7, 2026

Supersedes pending Stripe checks above. Sandbox success, card decline and
abandonment verified through Stripe; IDs in `docs/SUPPORT_DELIVERY.md`.
Approved live checkout configured and read back; no real payment submitted.
Eight Node site tests and `git diff --check` pass. Desktop support section
visually inspected and its button opened the exact approved live product.
No CSS changed; mobile rendering was not re-inspected in this follow-up.

Deployment: https://5c0693c2.barline-site.pages.dev (staging alias updated).
Home/About/privacy return 200 and match local bytes; missing route returns 404
and matches local 404. All four retain strict CSP and noindex headers.

- Home SHA-256: `2dcb0006eb2aaa535ab41af907d9a130756b229528728fe757a7a733a79aded3`
- Privacy SHA-256: `437661c5e7019811df3f388d583c6412c77610a33d0ef1c70a2466fd9157975a`
- About SHA-256 unchanged: `5ee300a4bfc7b7546095ce542d2882a3a1a4ecb8636045715b9ab5e09ca520cc`

The contribution link accepts real payments; staging explicitly says so.
Public domain, download/release and update feed were not activated.
