# Website qualification checklist

Website QA is separate from application qualification. This checklist is not a
certificate for the current source or any production deployment.

## Automated local checks

Run `npm test` and `npm run build` from `site`. Retain the source SHA and output
hashes with the results. Check semantic pages, local links/fragments, availability
copy, About attribution, support/privacy copy, strict headers, payload bounds,
and rejection of unexpected files or symlinks.

## Browser checks

- Inspect desktop and narrow mobile widths with no horizontal overflow.
- Traverse navigation, disclosure, support, About, and privacy links by keyboard.
- Verify Enter/Space disclosure behavior, visible focus, and sensible reading order.
- Check zoom, reduced motion, text contrast, and readable wrapping.
- Confirm the illustration is labeled as a demonstration, not a product screenshot.
- Inspect actual rendered viewports. Blank compositor frames or duplicated
  stitched captures are failed evidence, not proof of a correct render.

## Hosted checks

- Home, About, and privacy return 200 and match the approved built content.
- A missing route returns a real 404 with its expected body and security headers.
- CSP, no-referrer, nosniff, and framing protections remain in place.
- Preview retains noindex and honest pending-download/real-payment disclosure.
- Production domain/TLS, redirects, canonical links, and indexing policy match
  the approved launch scope.
- Download links resolve to the exact qualified signed binary and corresponding
  source, not a draft candidate or an upstream Ice release.

## Contributions and support

Verify checkout amount boundaries, success, decline, and abandonment in sandbox.
Verify the approved live link separately without an unauthorized real charge.
Ensure optional support never implies paid features or tax-deductible charity.
Privacy copy must explain Stripe processing and merchant-visible transaction
information. See [support delivery](../docs/SUPPORT_DELIVERY.md) for notification
and issue-intake checks.

## Evidence boundaries

Staging visual, functional, sandbox, and live-link checks were recorded on
September 7, 2026. They are historical observations, not a pass for later changes.
No real payment was submitted in the live-link check. Production domain and
public app-download qualification were not established by those checks.

Keep detailed receipts, deployment identifiers, screenshots, raw responses, and
hashes under ignored `.artifacts/site/`. Bind a new deployment to its exact built
content; a provider's source label alone is insufficient for a dirty-tree upload.
