# Barline execution plan

## Distribution refinement — 1.0.9 build 14

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
