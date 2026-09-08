# Reliability-first feature qualification

Next candidate: **1.0.11, build 22**. Installed baseline: **build 21**.
Implementation is not a release certificate.
Use the final source SHA and signed executable hash for every installed receipt.
Failed attempts remain in local evidence; do not replace them with a later pass.

## Implementation contract

- Display variants capture only the verified active menu bar display. Unknown,
  ambiguous, stale or empty displays are rejected. Replacement is explicit,
  edits stay in a draft, and save failures do not dismiss the editor.
- Rules are optional and event-driven. A change schedules one cancellable
  three-second settled-context check, not periodic polling. Configured native
  Focus, manual intent, current interactions and pending restoration take
  precedence. Admission is rechecked within the existing serialized transaction.
- Rules start paused on relaunch; Resume is explicit. Manual Command-drag,
  layout selection, history/recovery and workspace-setting changes pause them.
  Rules cannot restart other apps to change system item spacing.
- Per-item shortcuts reuse the existing item activation/restoration path. A
  press/release cycle dispatches once; held keys cannot build an action queue.
  Modifier release is bounded. Failed registration or persistence preserves
  prior intent and exposes unavailable state instead of pretending success.
- Rules, search personalization and item shortcuts have bounded private local
  stores. Corruption, cancellation, failed staging and competing writes do not
  overwrite the previously validated file.

## Evidence classes

| Area | Automated checks | Required installed / physical checks |
| --- | --- | --- |
| Display variants | Scoped capture, stale/disconnected/ambiguous rejection; existing reconnect resolver and transactional rollback tests | Capture/reopen/replace/remove on two displays; unplug/reconnect; notch and overflow |
| Rules | Predicate/priority/staleness tests; admission denial before effects, after journal, between moves and after workspace apply; real disk faults | Foreground app; power/battery where available; configured Focus on/off; native Command-drag/manual override; no self-generated retry loop; pause/relaunch/resume |
| Item shortcuts | Bounded model/duplicate validation; press-cycle tests; actual Carbon conflicts/suspension/recovery; real disk faults | Held/repeated keys; external-app conflict; native left-click and popover item activation; restoration and permissions |
| Groups/search | Group partition/order/collapse and local search tests; private preference fault injection | Keyboard traversal, Return/Space/Escape, favorites/aliases persistence, group rename/collapse and missing items |
| Core reliability | Strict build/lint/analyze; geometry, permission and recovery tests | Fresh upgrade/first click; bounded open/close burst with no failures; four native/popover journeys; helper interruption; journal restart |
| Accessibility | Semantic labels/control assertions and fixture audit | VoiceOver, Full Keyboard Access, contrast and reduced motion on the candidate |
| Distribution | Exact source, GPL notices, SBOM, signatures, notarization, staple, Gatekeeper, signed appcast | Clean install, update/rollback, published asset integrity and canonical site/download validation |

## Current boundary

The worktree now contains an additional observation-lifecycle repair (BLN-19):
old status-item window/screen publishers are canceled on replacement, nil clears
cached values, and queued delivery is canceled inside the switched owner stream.
Its standalone production-operator regression is a fast-gate check. Build-21
installed receipts below do not qualify this changed source. BLN-17 attribution
remains open independently.

Frozen build-21 source `59de12d` passed clean nonfocus qualification, real
preference fault probes, Carbon registration conflict/recovery checks,
Debug/Release compilation and analysis. The signed/notarized candidate passed
a preference-preserving Sparkle update, all four installed target-interface
journeys and one helper interruption. Installed checks cover single-display
variant authoring, rule editing while disabled, final-layout deletion and
shortcut-recorder accessibility exposure, not the full acceptance matrix above.

Additional installed checks cover temporary group creation, saved rename,
reopening and Escape cancellation preserving the prior saved group. The layout
was not applied. Forty-four focused search/group tests and real preference-store
fault probes passed; installed search interaction and shelf-group collapse remain
separate pending lanes.

A physical Control-Option-Command-9 fixture shortcut attempt on September 7
dispatched and opened/closed a native menu, but received no action click and
the maintainer reported nothing visible. A second, passively observed attempt
received exactly one activation/open/action/close. The fixture-owned menu was
on-screen, intersected the active display, and stayed open approximately five
seconds before the action. The restoration journal was empty afterward; the
temporary shortcut and fixture were removed. This proves one completed physical
native-menu shortcut journey, not repeatability or the cause of the first miss.
Both receipts and the fixture-only geometry trace remain in ignored
`.artifacts/local-acceptance-2026-09-07/shortcut-failure/`.

The initial installed shelf gate failed one opening cycle out of twenty.
Subsequent diagnostic runs passed but did not establish the cause; no passing
performance receipt replaces that failed attempt. BLN-17 remains open.
Physical hardware, native keyboard/Focus, VoiceOver, macOS 27, public-download
and production GO remain unclaimed. See the latest execution-plan checkpoint.

The earlier shelf-close miss remains recorded. The driver now treats a failed
close as a failed cycle and reacquires click geometry each time. This corrects
misclassification, but does not retroactively prove why that earlier click was
missed. Requalify the final candidate with retained raw cycle results.

## Visitor prerequisites

Private GitHub vulnerability reporting is enabled. The maintainer-confirmed
private conduct contact is dev@mabryventures.com. Preserve the current
development/download disclosure
until publication is authorized by passing release gates. Marketing drafts and
unrelated work must not be swept into a release commit.

## Hardware sequence

Complete and stabilize the current Mac's local qualification first. Then use
Jared's Work MacBook Pro for the notched-display and display-transition lane.
Naming that device is not evidence that it has been tested. macOS 27 remains a
separate runtime lane; do not upgrade either Mac merely to satisfy a gate.
