# Barline execution plan

This is the live implementation ledger. A milestone is complete only when its
code and evidence match the build specification; documentation alone is not a
gate result.

## Current checkpoint: production audit remediation, 1.0.7 build 8

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
