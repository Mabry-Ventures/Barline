# Reliability-first feature qualification

Candidate: **1.0.11, build 20**. Implementation is not a release certificate.
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

Local iteration has passed Core tests, real preference fault probes, actual
Carbon registration conflict/recovery checks, and Debug/Release compilation.
The latest edits require the complete gates again. No new installed feature,
physical hardware, macOS 27, public-download or production GO is claimed here.

The earlier shelf-close miss remains recorded. The driver now treats a failed
close as a failed cycle and reacquires click geometry each time. This corrects
misclassification, but does not retroactively prove why that earlier click was
missed. Requalify the final candidate with retained raw cycle results.

## Visitor prerequisites

Private GitHub vulnerability reporting is enabled. A monitored private conduct
contact is still needed. Preserve the current development/download disclosure
until publication is authorized by passing release gates. Marketing drafts and
unrelated work must not be swept into a release commit.
