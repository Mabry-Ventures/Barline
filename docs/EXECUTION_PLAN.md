# Barline execution plan

## Local-first qualification direction — September 7, 2026

The maintainer confirmed dev@mabryventures.com as the private conduct-report
contact; CODE_OF_CONDUCT.md now publishes it. Complete and stabilize the current
Mac's remaining runtime checks before using Jared's Work MacBook Pro for notch
and display-transition coverage. No test pass or release approval is implied by
the device selection. Keep the installed signed candidate and the original
BLN-17 failure evidence intact while narrowing the remaining local checks.

The shelf probe now distinguishes unexpected foreground UI from a timing
timeout, stops after the first opening failure instead of sending more clicks,
and emits buffered per-dispatch timing/flag metadata at exit. It collects no
coordinates, app names or outside input. Six deterministic cycle tests cover
success, timeout/baseline failures and interrupted opening/closing. These are
diagnostic corrections, not attribution or a product fix for the original miss.

## Build 21 qualification checkpoint — September 7, 2026

Frozen source `59de12d883c49d48b53b32d7874d4adff36ff76e`, installed
1.0.11 build 21, passed clean nonfocus qualification: 314 Core tests,
158 fixture/state tests, four fixture UI tests, Debug/Release builds and
static analysis. Packaging, notarization, staple and Gatekeeper passed.
The real build-20-to-21 Sparkle upgrade preserved semantic preferences,
the production feed and a single installed app process.

All four installed target-interface journeys passed on their first attempt:
native right, native left, popover left and popover reuse. Each witnessed
exactly one activation/open/action/close, the target's real accessible action,
the shelf staying closed during activation, hidden-position restoration and
pointer restoration. One forced helper interruption also recovered without
restarting the app. Deleting the final temporary layout now succeeds; shortcut
recorders are exposed in the installed accessibility tree. These observations
do not establish physical-keyboard or VoiceOver qualification.

**Release remains NO-GO.** The initial 20-cycle shelf gate failed cycle 9
with one opening timeout. Its failed log is retained, with no passing
performance receipt. The interval lacked both the product action log and
AppKit tracking/action messages; this narrows the investigation but does not
prove where input was lost. A traced 20-cycle run, buffered transport-observer
100-cycle diagnostic and corresponding 100-cycle run without that observer
passed. Passing diagnostics do not erase the original failure or establish a
root cause. No production workaround, extra click or automatic replay was added.

Temporary test layout, rule, shortcut and fixture process were cleaned up;
the installed signed candidate remains available. Build-20 and build-21 logs,
failed attempts, source/binary metadata and receipts are retained under ignored
`.artifacts/retained-qualification/2026-09-07-build20-21/`. Draft PR #6 contains
the implementation and visitor documentation; the Linux hygiene check passed.
No public release, update-feed activation or canonical download was published.

Outstanding: BLN-17 input-loss attribution; installed groups/search and
physical shortcut/Focus/manual-override checks; second-display/notch and power
transition hardware coverage; accessibility acceptance; private conduct-report
contact; final exact-candidate release gates. This host has one external display
and no macOS 27 runtime. Do not claim those unavailable lanes as tested.

## Installed qualification findings — September 7, 2026

Source `3400f35` (1.0.11 build 20) passed clean nonfocus qualification,
312 Core tests, 158 fixture/state tests, four fixture UI tests, strict
Debug/Release builds and analysis. Signed packaging/notarization, a real
build-19-to-20 Sparkle upgrade with retained preferences and one process,
20 shelf cycles (zero timeouts, p95 97 ms), and helper interruption passed.
Native left activation passed, but native right activation intermittently
failed twice: the target process received reveal/move events but no right
click, while the helper's session barrier reported delivery. Passing diagnostic
retries do not erase those failures. Public release remains blocked.

Build 21 restores the imported compatibility baseline's target-PID assignment
on the exact matched click at the session boundary, before exit acknowledgement.
No second mouse-down or automatic click replay is added. Regression tests cover
matched routing/payload preservation and nonmatching-event rejection. Passive
tap mutation is compatibility behavior, not an Apple API delivery guarantee;
fresh signed installed target-action qualification is mandatory.

Installed build-20 UI checks passed single-display capture, save/reopen,
replacement confirmation and discarded removal drafts. A temporary rule could
be created while global rules remained off. These are bounded checks, not the
physical-display, native Focus, power-transition or accessibility matrix.
The outdated read-only display-help text is corrected. Test data remains
explicitly named temporary until cleanup. Original failed evidence is retained
under `.artifacts/feature-installed/` in the clean qualification worktree and
will be copied into the main repository's ignored evidence storage.

Cleanup exposed a preexisting last-layout deletion restriction inconsistent
with the supported empty state. Build 21 permits an empty persisted local
catalog while retaining nonempty public archive validation. Regression tests
cover reopen, previous-layout backup and recovery from an empty backup.
The installed shortcut recorder also exposed a semantic grouping issue: its
buttons were visible but absent from the accessibility subtree in a nested
item row. Explicit child containment now preserves those controls; installed
accessibility verification remains required. A shortcut was recorded for the
synthetic native fixture, but a tool-generated chord did not establish global
Carbon dispatch, so no physical-keyboard activation pass is claimed.

## Feature completion and visitor cleanup — September 7, 2026

Candidate 1.0.11 build 20 integrates display-variant authoring, opt-in event-driven
context rules and per-item shortcuts, alongside existing groups, search
personalization and native Focus guidance. The implementation/qualification
contract is [FEATURE_QUALIFICATION.md](FEATURE_QUALIFICATION.md). Editors retain
failed-save drafts; rules recheck admission through the transaction, never
restart other apps for spacing, pause after manual changes and start paused
after relaunch. Shortcut conflicts, suspension and teardown now retain explicit
ownership and fail closed.

Visitor documentation and issue templates are corrected; detailed operational
documents were preserved in ignored local backups. Private vulnerability
reporting was verified enabled. A monitored private conduct contact remains a
user choice. An unrelated awareness-campaign draft appeared during this work;
it is preserved and excluded from engineering changes.

Iteration evidence includes passing Core regression suites, actual preference
write/cancellation/corruption/conflict probes, actual Carbon registration checks
without event injection, Debug/Release builds and the fast gate at
`.artifacts/ci/946e116047562599723ab7adce2a787b17d886e1/fast-2026-09-07T23-33-40Z`.
Subsequent changes require fresh full gates. Installed 1.0.10 build 19 remains
untouched during source work. No feature runtime pass, macOS 27 support,
notarization for new source or public availability is claimed by this checkpoint.

## BLN-17 diagnostic correction — September 7, 2026

Candidate `946e116` (1.0.10 build 19) was signed/notarized and installed through
a real preference-preserving Sparkle upgrade. Its final full gate failed one
of 20 shelf cycles; the original failure and four passing target receipts remain
under that source-bound artifact directory. Release has not been published.

The performance driver discarded a failed close, misclassifying the following
close as an opening timeout. It now rejects an unclosed baseline, fails the
actual close phase, resolves the owned status-item target for each dispatch,
and includes dispatch/lookup in latency. Four deterministic cycle regressions
are wired into the fast gate. These are test-driver corrections, not a proven
application fix for the original missed click.

Two bounded diagnostic runs on the unchanged signed executable passed: the
hardened 20-cycle probe (p95 163.5 ms including lookup/dispatch), and the original
rapid cadence with a temporary listen-only session event observer (all 42
clicks' down/up pairs observed). The latter ran alongside compilation and is
diagnostic evidence, not a clean performance certificate. No target movement
was observed in the hardened run. The original missed close is not reproduced
or conclusively attributed; BLN-17 and release qualification remain open.
No app relaunch, permission reset, target action bypass, or timeout relaxation
was used. Temporary observer code is confined to ignored artifacts.
Fast gate passed with the four new cycle regressions and 296 Core tests;
receipt: `.artifacts/ci/946e116047562599723ab7adce2a787b17d886e1/fast-2026-09-07T22-53-17Z`.
This dirty-tree iteration receipt is not a new release certificate.

Additional-feature status: groups and search personalization are implemented
but still need installed keyboard/persistence qualification; native Focus
guidance is implemented, display variants are read-only, automatic context-rule
integration and per-item global shortcuts remain unfinished. Site/donations
are on staging; the canonical public-domain launch remains separate.

## Fresh release qualification — September 7, 2026

User authorized release only after a new qualification battery passes. Candidate
1.0.10 build 19 includes the reviewed reliability-first app changes and retains
the installed 1.0.9 build 18 until a signed replacement is available. No previous
SHA's receipts qualify it. Run fast, full installed-candidate gates, signed
packaging, real upgrade, and the changed-feature/manual acceptance matrix.
Keep failures, exact source/binary hashes and runtime evidence under ignored
artifacts. Public release is conditionally authorized, never authorized on a
partial or bypassed gate. macOS 27 remains a separately unqualified OS lane.

## Reliability-first direction — September 7, 2026

The current forward plan is [RELIABILITY_FIRST.md](RELIABILITY_FIRST.md): core
reliability/speed first, guided native Focus/display layouts, explainable rules,
functional shelf groups, keyboard personalization, and a quiet donationware
site on Cloudflare Pages. macOS 27 compatibility now requires rigorous runtime
qualification; macOS 27-exclusive features are deliberately not day-one scope.
Older milestone snapshots below are historical, not current certificates.
Public release/update publication remains staged for final approval.

Implementation checkpoint on `codex/reliability-first`: accessible collapsible
shelf groups, local search favorites/aliases with atomic private persistence,
guided native Focus setup and honest read-only display-variant descriptions,
and a configuration-gated About support link are implemented but not installed
or runtime-qualified. The contextual-rule evaluator is proposal-only; safe
automatic application and per-item global shortcuts remain unfinished. Do not
treat them as shipped features. The working installed 1.0.9 build 18 is untouched.

Cloudflare Pages project `barline-site` now has an authorized `staging` preview.
`usebarline.com` is the user-owned canonical domain, not yet activated. Stripe
sandbox success/decline/abandonment are verified. Approved live one-time support
is configured and linked from staging with real-payment disclosure; public
domain/app release activation remains gated. BLN-9 records checkout evidence.
Barline Linear team (BLN) owns the roadmap (BLN-1–14). GitHub issue/comment
delivery to `#productsupport` and inbound Linear Triage sync passed a controlled
test. Linear posting to `#barline` is authorized and verified with creation and
comment receipts from BLN-16; roadmap/status/triage notifications are enabled. Ice credit moved
to the deployed About page. Receipts: [SUPPORT_DELIVERY.md](SUPPORT_DELIVERY.md).
Site delivery evidence is recorded
in [site/QA.md](../site/QA.md). New source invalidates prior candidate certificates;
the current checks are iteration evidence, not signed release qualification.

## Distribution refinement — 1.0.9 build 18 preparation

Build 17 (`f7478cf`) passed fast, signing/notarization, semantic upgrade, and
all four isolated fixture XCUITests. Installed qualification failed: one
restoration observation timed out and a later native-target move failed before
activation. Successful intervening popover runs do not erase those failures.
Build 18 guards both intentional drag dispatch stages against cancellation,
allows release to commit geometry without requiring an intermediate change,
and adds closed failure codes. Final placement checks remain unchanged.
Focused no-event regressions cover dispatch ordering and release sequencing.
Fresh full and signed installed proof remain mandatory; publication is staged.

Build 16 (`67399bb`) passed fast, signing/notarization, and upgrade/preferences.
Its first shelf presentation committed, but closed roughly 400 ms later before
fixture controls became actionable; the installed journey therefore failed.
Build 17 applies primary control hit ownership to smart rehide as well as
empty-space arbitration, including windowless hosted events with stale bar
geometry. Shelf clicks are similarly excluded using captured event geometry.
Deferred dismissal reasons now have bounded diagnostics. Policy regressions
cover each exclusion and the genuine outside-click positive control. This is
not runtime qualification until the new candidate passes its installed gates.

Build 15 passed signing/notarization, upgrade/preference checks, and 263 Core
tests, but its first installed shelf-open journey failed. The deferred-work
lease does not prevent a second handler from toggling the same current click.
Build 16 makes control-window target ownership authoritative even with stale
geometry and uses the event's captured coordinates in click arbitration.
Ownership checks read the live status button's window and geometry synchronously rather
than relying only on its queued published window after a button replacement.
A Core regression covers a control-window event with all geometry claiming
empty space. Installed runtime proof remains mandatory.

User authentication now permits XCUITest execution. Its fixture-only status
tests failed because the concurrently running Barline hid those fresh items;
qualification must isolate that lane from the installed utility, then reopen
the exact candidate once for installed runtime gates. This is separate from
the observed first-click product failure. All failed attempts remain retained.

Build 14 passed signing/notarization, a semantic-preference-preserving signed
upgrade, all four installed target lanes, 20 shelf opens (p95 47.3 ms), and one
helper replacement with preserved app PID. The five-open follow-up failed one
sample: generation 49 began and was immediately closed without another control
action. All evidence remains under its source-bound artifact directory; the
six passing receipts do not override the failed enclosing burst gate.

Review found delayed smart-rehide work had no presentation ownership and read
the later pointer location. Build 15 captures the original event location and
binds smart, timed, hover, and focused-app delayed dismissals to a presentation epoch.
Closing/reopening invalidates earlier dismissal leases. Four pure regression
cases cover current, closed, reopened, and repeated presentation lifetimes.
This closes a demonstrated code-level race consistent with the retained trace;
the prior logs do not conclusively identify which dismissal caller fired.
Fresh installed qualification is required. UI Automation authentication remains
an independent external gate; public publication remains approval-gated.

Build 13 passed four consecutive installed target-action/restoration lanes and
direct restart-recovery UI checks. Its full gate passed builds, analysis,
Core/integration execution, fixture, semantic accessibility and privacy checks.
XCUITest hit a distinct macOS authentication boundary: automation mode is
disabled and requires user authentication, despite DevToolsSecurity being enabled.
The performance harness also rejected a verified hosted icon's two-point width
difference; build 14 fixes that comparison with eight regressions and keeps the
250 ms budget unchanged. A focused real click then passed at 23.7 ms. That single
sample is not the required 20-sample candidate performance certificate.

Build 12 passed signing/notarization and a localhost Sparkle upgrade, but failed
its first installed hidden-item action gate. The new checkpoint required display
ownership while the helper supplied physical intersection only, leaving hidden
off-screen items unresolved. Build 13 separates logical WindowServer ownership
from physical click visibility, including restoration destination selection.
The working 1.0.8 install was restored while correcting this failure. All build
12 artifacts remain rejected qualification evidence. Public release and update
feed activation are staged for the user's final approval, not authorized now.

The September 7 follow-up audit identified mutable-neighbor restoration and
candidate-receipt enforcement gaps. Temporary reveals now carry a durable,
bounded checkpoint of the original display/section plus ordered stable anchors.
Moved/missing anchors cannot redirect restoration; unavailable topology pauses
for explicit recovery, and three failed attempts stop automatic retrying.
After restart, retained entries require Retry Item Restoration in Layouts & Focus
rather than silently overwriting possible outside-app edits.

New authoritative layout operations are blocked while compensation remains;
they never discard a pending reveal before an operation that might roll back.
Manual dragging first attempts restoration. Focus/layout failures explain the
recovery prerequisite. Core tests cover the guard, journal and resolution policy.

The installed full gate already called performance and XPC interruption through
the reopen-burst script; the audit's claim that these were entirely skipped was
too broad. This refinement makes their receipts explicit and mandatory, together
with four actual target-interface lanes, exact source SHA and executable hash.
Receipt validator/writer tests cannot themselves certify runtime behavior.

Build, signed candidate qualification, and distribution preparation are in
progress. No new runtime, notarization, upgrade or public-release success is
claimed by this implementation checkpoint. macOS 27 and soak remain deferred.

This is the live implementation ledger. A milestone is complete only when its
code and evidence match the build specification; documentation alone is not a
gate result.

## Current checkpoint: shelf activation correction, 1.0.8 build 11

The installed 1.0.7 user journey exposed a real regression: a temporarily
revealed native item remained in the shelf projection, and a no-interface
timeout reopened the picker. Logs also captured presentation during an active
click. The corrected candidate blocks picker presentation during activation
and restoration, excludes outstanding temporary reveals from shelf rendering
without changing saved layout authority, and keeps an unconfirmed click distinct
from a failed operation. Unconfirmed clicks no longer reopen the picker over a
possibly delayed target interface.

The helper click path now follows the exact vendor baseline's session dispatch
with source-queue null barriers, cleared modifiers, and down/up click states
1/0. Real clicks are not directly reposted to the source PID; passive delivery
acknowledgement is still not target activation proof. The synthetic journey must
observe the target menu/action and restoration on the signed installed candidate.
Current iteration: 221 Core tests and three production event-delivery ordering
tests pass. A shelf-only screenshot proved fixture items rendered while their
representable wrappers exposed no actionable AX buttons; explicit SwiftUI
accessibility semantics now wrap the native pointer controls. Compilation and
signed runtime qualification continue. The first signed iteration has passed
the installed synthetic native-menu and custom-popover journeys, including
target actions and position restoration. The harness now verifies the fixture's
hosted autosave-name alias instead of assuming its rendered text is its AX label.
These results must be rebound after this gate correction changes the source SHA.
No public release or production GO is implied.

The second signed iteration (`a7f6e72`) also passed native-menu and popover
activation, action, closure, and original-position restoration with a stricter
visible-action resolver. Earlier failures are retained, not discarded: a menu
opened and closed without its action receipt, and another run missed its short
visible interval. The gate now requires a unique, enabled, on-screen,
fixture-owned action with the expected menu-item or button role. This prevents
stale or wrong-interface selection; it does not establish that as the cause of
every earlier failure. The final source-bound package must rerun these journeys.

The subsequent `05525e3` native journey passed after a fresh background launch,
but its popover attempt produced no fixture activation. This remains a failed
candidate, despite its passing fast/signature/notarization gates. Baseline
comparison found two omitted protocol details: paired mouse-up releases and
consumption of source-queue null barriers. Build 10 restores these and the
baseline's balanced cursor hiding instead of drag-style cursor disassociation.
No second mouse-down or full-gesture retry is introduced. The installed journey
now fails on duplicate activations, opens, actions, or closes; exactly one of
each is required. Source parity is a hypothesis to validate, not a runtime pass.

The bounded build-10 observer established the actual popover failure: the
synthetic hosted item retained `kCGWindowIsOnscreen = true` while both its CG
and AX frames were outside every active display. Its frame and target receipt
did not change during the failed journey. The app therefore took its direct
activation branch and clicked off-display instead of temporarily revealing it.
Build 11 derives menu-item visibility from the reported flag AND a finite click
center inside an active display. Hidden descriptors remain in the inventory;
generic interface observations keep their existing visibility semantics. The
helper checks fresh geometry again before any click side effects. Regression
tests cover the observed stale-flag condition and multi-display geometry.

The September 6 audit found 12 issues in `b03645e` (installed 1.0.6).
The historical milestone table below is not qualification evidence for this
replacement. Follow [the finding ledger](PRODUCTION_REMEDIATION.md) for current
implementation and candidate-bound gates. Scope includes activation and return
transactions, ownership continuity and legacy layout identity migration, real
menu tracking, permission reconciliation, runtime-log privacy, Sparkle 2.9.6,
native shelf accessibility, image fallback, bounded off-main search/icon work,
and an explicit [auto-hide support boundary](SUPPORTED_CONFIGURATIONS.md).

Release validation is in progress. Local builds and focused tests are iteration
evidence only until rebound to the final clean source SHA. The installed-target
journey must observe the target menu and receipt, not just shelf visibility.
Repeated Settings-foregrounding gates have been replaced by bounded shelf and
helper-recovery probes. macOS 27 and release-duration soak remain user-deferred.

Final integration review added cancellation-independent serialized compensation,
capture permission epochs checked at UI publication, initial/late-window
auto-hide discovery, and image-owning native shelf buttons. The 219-test Core
iteration and Debug build pass. New fixture event-receipt qualification remains
red on this host (XCTest delivered no activation); the independent installed
journey has opened the shelf but has not yet established target activation.
These are explicit pending gates, not a production GO or permission to bypass
the protected local check. Updated signing/install validation continues locally.

| Milestone | Owner | Status | Dependencies | Evidence |
| --- | --- | --- | --- | --- |
| 0. Import and provenance | Lead; delegated audit | Complete | none | Exact history, remotes, ancestor proof, vendor tag, license/provenance records |
| 1. Baseline build and audit | Lead; delegated audits | Complete | M0 | Debug/Release/analyze/archive and policy scripts pass; permission-gated launch; result bundles |
| 2. Rebrand and build system | Lead | Complete | M1 | Debug/Release/analyze pass; strict lint 0 violations; canonical Run verification pass |
| 3. Core and compatibility firewall | Lead | Complete | M2 | 193 Core tests; strict source/binary firewall; helper generation rebasing, absolute mutation deadlines, session-cancellation quiescence, durable authority rehydration, fail-closed recovery, and pure shelf-presentation commit policy |
| 4. Fixture and local CI | Lead; delegated validation | Exact-head full gate passing | M3 | `ci.sh full --publish-status` passes on the exact candidate with 180 Core tests, 134 fixture regressions, fixture XCUITest, semantic accessibility, privacy, XPC interruption, UI smoke, a 20-cycle performance probe, and the 100-cycle plus eight helper-recovery reopen burst; retain the ignored `.artifacts/ci/<sha>/` packet |
| 5. Profiles and Focus | Lead | Native layout filter implemented; exact-head system execution pending | M3–4 | Apple Focus Filter selects any saved Barline menu bar layout by stable identifier; Barline links to the system-owned Focus configuration because Apple exposes no public Focus-mode catalog; configured app-group store, bounded import, generation-checked workspace/layout/presentation history and rollback, atomic crash-recovery authority envelope, exact-target promotion, original-state recovery, unrelated-state preservation, durable Focus journal, and conservative display reconnect; exact-head signed Focus activation/deactivation remains required |
| 6. Search and on-device interpretation | Lead | Complete for macOS 26 | M3–5 | collision-free opaque item identities, deterministic ranking, bounded and serialized latest-wins Spotlight replacement, cross-display metadata, 180 Core tests; macOS 27 tool remains gated |
| 7. UI and accessibility | Lead | Exact-head automated validation passing | M3–6 | profile UI, fixture UI, diagnostics review/save, fixture XCUITest, and semantic accessibility pass on the exact candidate; foreground VoiceOver and Full Keyboard Access remain manual validation lanes |
| 8. OS hardening | Lead | Shelf commit hardening implemented; exact-head full gate pending | M3–7 | Shelf presentation now sizes before ordering and requires two consecutive AppKit plus helper-owned WindowServer confirmations when that observer is available. A valid local AppKit presentation remains ordered when unrelated helper work delays WindowServer observation, so observer availability cannot roll back a user click; invalid local geometry still retries and fails closed. The semantic helper probe bypasses mutation serialization, never exports ephemeral window IDs, and cannot invalidate the shared session on its bounded timeout. The runtime harness has a real status-item click lane pinned to the exact app PID and window number. Exact-head full/candidate testing, physical scenario matrix, release soak, and macOS 27 remain pending. |
| 9. Distribution readiness | Lead | Notarized 1.0.5 installed; replacement candidate validation in progress | M0–8 | Developer ID export, App Group profile validation, notarization, stapling, Gatekeeper, Sparkle signing, checksums, SBOM, and source archive passed for installed 1.0.5; exact-head evidence must be regenerated for the helper-independent shelf presentation correction. |

## External boundaries currently known

- Xcode 27 beta 6 / Swift 6.4 is not installed.
- No macOS 27 runtime host is available, so runtime compatibility cannot be claimed.
- The canonical `Mabry-Ventures/Barline` repository, `origin`, protected ruleset,
  and pull request exist; the protected local macOS check is published from the
  exact candidate full gate.
- A valid Mabry Ventures Developer ID identity and Barline App Group
  provisioning profiles exist locally. Keychain authorization is configured,
  and a Developer ID export has passed nested signature validation.
- Sparkle signing material and the full credentialed release path pass locally.
  The `barline-notary` profile is stored in the login Keychain; release tooling
  selects that Keychain explicitly to avoid a same-named stale credential in a
  different backend. Exact-head release validation uses this explicit
  credential-selection path.
- Developer Tools automation mode and the fixture accessibility path have been
  validated. The production reopen-to-visible p95 gate necessarily activates
  Barline and was run in a dedicated unlocked interactive session; Barline is
  closed after each runtime gate.

The lead owns all project-file, scheme, test-plan, configuration, entitlement,
identifier, dependency, and integration changes. Delegated audits are advisory
until their findings are incorporated and rerun by the lead.
