# Production remediation — 1.0.8 (build 9)

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
