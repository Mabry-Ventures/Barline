# Contribution and support delivery checkpoint

## Live support follow-up — September 7, 2026

This supersedes the pending Stripe items in earlier checkpoints below. User
completed sandbox tests and explicitly approved live setup plus staging upload.

- Success: `pi_3UDAFSC5zaZbCeEp0zkNkbw9`, succeeded, USD 1000 received;
  checkout complete/paid, sandbox only, no subscription.
- Decline: `pi_3UDAMqC5zaZbCeEp256LiKAj`, requires_payment_method,
  card_declined/generic_decline, zero received. Screenshot shows the error.
- Abandonment: `cs_test_a1A9l4NwodgG72miI0aonrTL7tsvVD68bVG8PZyaO9jnkdxXbXr3BLIaZV`,
  USD 1100, open/unpaid, no PaymentIntent. User closed without submitting.
  This proves abandonment, not cancellation of an existing payment.

Live Mabry Ventures LLC account has charges/payouts enabled, no disabled reason.
Created product `barline-support`, price `price_1UDAQCFr1wB9mCUGaHLC030c`, and
Payment Link `plink_1UDAQQFr1wB9mCUGx7aFkbfA`:
https://buy.stripe.com/cNibJ1a370l33AVgnk1ck02
Readback: active/live, one-time USD, $10 preset/$1–$500 bounds, quantity one,
no subscription, invoice or future-payment setup. API specifies card; hosted
Stripe UI also offers Apple Pay/Link and Link-powered bank/Klarna options.
No account-wide payment settings changed. No real payment submitted or verified.

Staging links to live checkout with explicit real-payment disclosure. Privacy
explains Stripe processing and merchant-visible transaction information. Eight
tests pass; preview `5c0693c2` matches tested bytes and retains noindex/CSP.
Site-to-checkout navigation and live product/$10 copy verified in browser.
No embedded payment code, credentials, webhook, or app entitlement added.
Public domain, app release and update feed remain staged for final approval.

## Current checkpoint — September 7, 2026, 21:07 UTC

This section supersedes the earlier account/sign-in/routing blockers below.
No production domain, live payment link, app release or update feed activated.

### Stripe

User confirmed Mabry Ventures LLC live account, sandbox first. Required planner
accepted: `iguide_61VMXR0iheOd7cjO241C5zaZbCeEp`. Sandbox product
`barline-support`, price `price_1UD9YIC5zaZbCeEpk9SX8nk8`, Payment Link
`plink_1UD9YqC5zaZbCeEpLpJr5mqR`:
https://buy.stripe.com/test_fZu5kCeHU0yJeOF3aneZ202

One-time USD, suggested $10, customer chooses $1–$500. Hosted minimum and maximum
validation passed. Card-only methods; no subscription, invoice, future-payment
setup, paid unlock, app SDK, card form or webhook. Describe optional support/tips
for free Barline software, not charitable or tax-deductible donations.

Test checkout remains open/unpaid. User-completed sandbox payment requested
after checkout presented an AI purchase attestation/Link flow. Success, decline
and cancellation proof remain incomplete. No live objects created. Complete
sandbox qualification before creating/readback of live checkout and updating
the website support/privacy copy. Never infer payment success from navigation.

### GitHub to Slack: positive delivery proof

Workspace Mabry Ventures; `#productsupport` = `C0C05BZ92RY`.
Previously unsubscribed. Configured existing GitHub app:
`/github subscribe Mabry-Ventures/Barline issues comments:"channel"`.
No label filter or unrelated channel/repository changes.

- Subscription: https://mabryventures.slack.com/archives/C0C05BZ92RY/p1788814426419769
- Test issue #5 delivered at 21:05:53 UTC:
  https://mabryventures.slack.com/archives/C0C05BZ92RY/p1788815153416409
- Follow-up comment delivered at 21:06:07 UTC, broadcast in channel:
  https://mabryventures.slack.com/archives/C0C05BZ92RY/p1788815167655929
- Test https://github.com/Mabry-Ventures/Barline/issues/5 closed as not planned
  at 21:06:44 UTC, not deleted. Earlier negative test #4 remains historical.

Channel preferences: all new posts, mobile notifications on/all posts, badge
every message, follow every thread. Browser desktop push needs browser
notification permission. No global DND, schedule or OS privacy change was made.
Delivery is proven; actual mobile/desktop banners have not been witnessed.

### Linear: team, roadmap and inbound sync

Created **Barline (BLN)**, ID `c515eb80-cca6-4e5f-a306-8968285b4f85`.
BAR already belongs to Barkopolis. Jared is a member; timezone Chicago.

- Reliability-first release:
  https://linear.app/mabry-ventures/project/barline-reliability-first-release-c85359e58a58
- Website/support launch:
  https://linear.app/mabry-ventures/project/barline-website-and-support-launch-464ef9f7eea4
- macOS 27 compatibility:
  https://linear.app/mabry-ventures/project/barline-macos-27-compatibility-b59976c549aa

BLN-1–14 track current roadmap, acceptance criteria, Jared ownership, and
release/OS dependencies. BLN-10 (About staging) is Done. Unqualified application
features remain open. Linear owns work/roadmap tracking; repository documents
retain architecture and evidence contracts.

Native GitHub integration links `Mabry-Ventures/Barline` to BLN using one-way
issue creation. Internal roadmap issues do not create public GitHub issues.
IMPORTANT: properties and replies in the explicitly synced comment thread of
already-linked issues still sync both ways. Keep internal discussion outside
that public synced thread. No unrelated repository or public linkback changes.

No open GitHub issues existed to import. Test #5 automatically created BLN-15 in
Triage; follow-up comment synced; GitHub closure moved BLN-15 to Canceled:
https://linear.app/mabry-ventures/issue/BLN-15/routing-test-verify-barline-github-to-slack-and-linear
Triage is enabled, requires explicit prioritization and notifies Jared.
AI triage suggestions are off; no automated agent loops configured.

### Linear to #barline: authorized and verified — 21:33 UTC

Existing `#barline` channel = `C0BVD51S411`. Settings:
https://linear.app/mabry-ventures/settings/teams/BLN/notifications
User explicitly approved the incoming-webhook permission. Slack consent completed
in Chrome; team settings show #barline Connected. Enabled project updates, new
team issues, completed/canceled issues, other status changes, comments and triage
arrivals. SLA-specific categories remain off.

Controlled BLN-16 test created and then canceled (not deleted). Both creation and
comment reached #barline through Linear integration `B0BVD9M1FDH`:

- Creation: https://mabryventures.slack.com/archives/C0BVD51S411/p1788816760024739
- Comment: https://mabryventures.slack.com/archives/C0BVD51S411/p1788816758481629
- Canceled status: https://mabryventures.slack.com/archives/C0BVD51S411/p1788816788810009

GitHub issue inventory still contained only the earlier closed tests #4/#5;
this internal Linear test did not create a public GitHub issue. BLN-11 records
completed routing setup. Actual OS/mobile banners remain a separate caveat above.
IAB did not expose OAuth popups; Chrome completed the scoped consent correctly.

### Website and attribution

User approved moving footer credit to About. New About preserves Jordan Baird's
Ice, Xinyan Lu's compatibility fork, GPLv3-or-later, provenance/source/notices,
and independent/non-endorsement language. Distribution/source notices untouched.
https://staging.barline-site.pages.dev/about/

Seven tests pass. Preview `31862687` has matching local/deployed home/About/privacy
bytes, HTTP 200/404, strict security/noindex headers. About desktop and 390px
mobile renders checked without horizontal overflow. See `site/QA.md`.

References: https://linear.app/docs/github ; https://linear.app/docs/slack ;
https://docs.stripe.com/payment-links/create?pricing-model=customer-chooses ;
https://support.stripe.com/questions/requirements-for-accepting-tips-or-donations

## Earlier checkpoint (superseded where noted above)

September 7, 2026. The existing Pages preview remains unchanged; no live
contribution link, custom domain or app release was activated in this check.

## Stripe

Reauthentication succeeded. The connector exposes Mabry Ventures LLC (live)
and Mabry Ventures LLC sandbox. Receiving-account confirmation is pending.
The intended flow is optional one-time, customer-chosen support through a hosted
Payment Link. No app entitlements, account, payment SDK or webhook is needed.
Run the required integration planner after account selection, qualify sandbox
checkout, then create/read back the live configuration and update the site.
Do not characterize contributions as charitable or tax-deductible.

## GitHub to Slack

Connected Slack workspace: Mabry Ventures. GitHub is installed and other
repositories' workflow notifications are arriving in `#alerts`. No Barline
channel or recent Barline GitHub message was found. An empty repository-webhook
list does not disprove a GitHub App subscription. GitHub watch-state API access
lacks the notifications scope and is not a substitute for Slack routing proof.

Controlled test: https://github.com/Mabry-Ventures/Barline/issues/4
Created 20:40:21 UTC; a follow-up comment was added; no matching message was
observed in connected Slack search or the latest alerts history by 20:41:41 UTC.
The test issue was closed, not deleted. This bounded negative observation is
not proof that delivery can never occur; routing remains unverified.

The native Slack app did not respond reliably to automation. Web sign-in reached
Google's password prompt for the existing workspace identity; user sign-in is
pending. No credentials were retrieved, entered or changed.

After access is restored:

1. Resolve/create the dedicated Barline support channel and ensure Jared is a
   member. Verify the GitHub app's current subscriptions with
   `/github subscribe list features`.
2. Subscribe to `Mabry-Ventures/Barline issues comments:"channel"`, without label
   filters. Preserve unrelated channels' subscriptions. Do not add a workflow
   or custom webhook where the native integration suffices.
3. Set this channel to all new posts, desktop/mobile notifications and thread
   replies as appropriate. Check muted state and notification schedule; do not
   change global Focus/DND or OS privacy settings without scoped approval.
4. Repeat a labeled test issue and reply, verify real Slack message permalinks,
   then confirm actual alert behavior with the user. Close the test issue.

Sources:
- https://docs.github.com/en/integrations/how-tos/slack/customize-notifications
- https://github.com/integrations/slack#broadcast-comments-and-reviews-to-channel
- https://slack.com/help/articles/360056534254-Manage-notifications-for-specific-channels-and-direct-messages

## Attribution

The repository's GPLv3-or-later license, NOTICE, provenance and upstream history
remain intact. No footer-specific requirement was found in those materials.
A footer Credits link can lead to full attribution for Jordan Baird's Ice,
Xinyan Lu's compatibility fork, licensing and corresponding source. Website
wording is not a substitute for notices/source obligations in distributed apps.
The current footer was left unchanged because the user asked whether it is
required, not explicitly to remove it.
