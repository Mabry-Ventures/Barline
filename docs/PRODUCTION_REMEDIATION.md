# Production remediation — 1.0.9 (build 17 preparation)

Build 16 committed the first shelf presentation but failed the installed target
journey when it closed before its accessible item controls appeared. Build 17
extends primary hit ownership to smart rehide (not only global toggle), covers
windowless shelf clicks, and records bounded deferred-dismissal reason codes.
Previous package signatures and fast results do not qualify this source.

Build 15's first installed shelf-open failed despite the deferred-dismissal
guard. Build 16 also enforces primary-window ownership of click events and
uses immutable event coordinates rather than later cursor snapshots for global
empty-space arbitration. A stale-geometry ownership regression was added.
The XCUITest authentication boundary was cleared for execution; fixture-only
tests require isolation from the running utility's intentional item hiding.

Build 14's required six receipts passed, but its enclosing burst gate failed
one post-recovery open. Delayed dismissal tasks could outlive the presentation
that scheduled them. Build 15 scopes smart/timed/hover/focused-app rehide to an epoch
and captures the initiating click position before helper awaits. Four regression
cases cover ownership invalidation. Installed proof must be regenerated; do not
promote build 14 to distribution GO on its six receipts alone.

Build 14 corrects a measured test-harness mismatch: macOS hosts the source AX
status button with identical center but two points of width difference. The
installed journey already tolerated that layout; the performance probe did not.
Eight shared-policy regressions cover this and reject unrelated/invalid geometry.
The 250 ms performance budget is unchanged. XCUITest remains separately blocked
by macOS requiring user authentication to enable UI Automation.

Build 12's signed installed journey rejected hidden-item activation before any
target click because off-screen bounds produced no display identity. The helper
now resolves logical WindowServer display ownership for both snapshots and move
destinations; physical click visibility remains a separate safety check. Build
12 is retained as failed qualification evidence, not silently replaced by a pass.

September 7 refinement: original-section/display restoration uses stable anchor
fallbacks and a durable bounded journal; unavailable topology or three failed
attempts pause for explicit recovery. Restarted entries are not auto-applied.
Manual/profile/history changes cannot erase pending reveal intent before success:
they wait for restoration. A Retry Item Restoration control is in Layouts & Focus.

Installed qualification now requires four target-interface lanes plus measured
performance and helper-recovery receipts bound to both source and executable.
The historical reopen gate already ran performance/recovery indirectly; the
actual gap was mandatory retained evidence, not total absence of those calls.
No public feed/upgrade or new candidate qualification is claimed until its
release artifact directory records that evidence.

Baseline: `b03645e432212aed10a827d3334ce278770fb74d` (1.0.6 build 7).
The September 6 production audit is retained under `.artifacts/audit/2026-09-06-b03645e/`.
This ledger distinguishes implementation from actual release qualification.

1.0.7 installed feedback confirmed F01 remains open: direct-PID click delivery
can acknowledge transport without status-item dispatch, and the shelf can
reappear during a temporary reveal. 1.0.8 restores baseline-shaped session
click routing and separates confirmed/unconfirmed/failed outcomes. The shelf
excludes items with outstanding native restoration obligations and does not
present during activation/restoration. These are implementation changes until
the signed candidate's target-receipt journey passes. The journey's bounded
AX hit-test diagnostic fallback explicitly retains a failed AX traversal lane;
it cannot promote pointer interaction evidence into an accessibility pass.
The installed journey additionally requires a unique, visible, fixture-owned
target action of the expected role. Candidate logs retain failed attempts as
well as successful native-menu and popover action/restoration witnesses; one
successful attempt is not broad compatibility or full production readiness.
Build 9's final popover attempt failed without a target activation. Build 10
restores the baseline's paired releases, swallowed null-barrier signals, and
balanced cursor hiding. The gate requires exactly one activation/open/action/
close and rejects duplicates; these compatibility corrections require fresh
candidate-bound runtime validation.
The build-10 frame observer then proved the failing hosted item was marked
on-screen while physically outside every display, bypassing reveal. Build 11
corrects menu-item visibility using active-display click geometry and rejects
off-display synthesis at the helper boundary. This is supported by unchanged
synthetic CG/AX frames and target counters throughout the captured failure,
not an inferred permission or timing issue.

| Finding | Change | Acceptance evidence |
| --- | --- | --- |
| F01 activation | Shared validated presentation/action snapshots, explicit ownership, fresh identity resolution, recoverable activation failures | Pending candidate journey |
| F02 updater | Sparkle 2.9.6 security fixes; regenerated lock | Pending built framework/signature check |
| F03 distribution | Canonical source/support links; signed appcast publication | Pending live release/feed and upgrade |
| F04 permissions | Contextual nonprompting authority; revoke/in-flight invalidation | Adapter transition test; actual TCC pending |
| F05 privacy | Bounded reason codes, no item/title/ID dumps | Synthetic formatter and separate runtime-log gate |
| F06 menu tracking | Helper-owned native/custom interface observation, synthesis exclusion, and coordinator interaction leases across reveal/click/restore | Core policy and concurrent Focus/undo/refresh lease tests; candidate native/popover journey pending |
| F07 release gates | Fixture target receipts, actual signed-app interaction harness | Pending candidate journey |
| F08 keyboard | Native shelf buttons, default AX action, arrows/Return/Space/Escape and Control-click | Actual keyboard/AX pending |
| F09 captures | Stable-ID image keys and always-present metadata fallback | Partial capture/duplicate identity pending |
| F10 stale view | Updated native callbacks/labels and action-time fresh resolution | Candidate reuse pending |
| F11 auto-hide | Explicit compatibility boundary and direct menu-bar fallback | Runtime alternative pending |
| F12 UI work | Cancellable cached search actor; bounded normalized icon imports | Focused search/import tests |

Release eligibility requires the corrected candidate's local gates and target-interface interaction, not shelf visibility alone. A new source SHA invalidates older package evidence. macOS 27 runtime and release-duration soak remain explicitly deferred by the user. No macOS or self-hosted GitHub Actions runners are permitted.

Final review hardening: register restoration obligations before movement so a
cancelled post-move verification cannot strand an item. Retain observations for
already-visible custom interfaces until closure, without retaining mutation
authority during user interaction. Fixture-only qualification and the installed
hidden-item journey remain separate proof classes; failure of either is not a
passing production interaction result.
