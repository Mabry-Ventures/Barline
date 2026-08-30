# Barline execution plan

This is the live implementation ledger. A milestone is complete only when its
code and evidence match the build specification; documentation alone is not a
gate result.

| Milestone | Owner | Status | Dependencies | Evidence |
| --- | --- | --- | --- | --- |
| 0. Import and provenance | Lead; delegated audit | Complete | none | Exact history, remotes, ancestor proof, vendor tag, license/provenance records |
| 1. Baseline build and audit | Lead; delegated audits | Complete | M0 | Debug/Release/analyze/archive and policy scripts pass; permission-gated launch; result bundles |
| 2. Rebrand and build system | Lead | Complete | M1 | Debug/Release/analyze pass; strict lint 0 violations; canonical Run verification pass |
| 3. Core and compatibility firewall | Lead | Complete | M2 | 180 Core tests; strict source/binary firewall; helper generation rebasing, absolute mutation deadlines, session-cancellation quiescence, durable authority rehydration, and fail-closed recovery |
| 4. Fixture and local CI | Lead; delegated validation | Exact-candidate fast pass; full rerun pending after review fix | M3 | fast passes with 180 Core tests; the immediately preceding candidate passed Debug/Release/analyze, test-plan execution, 134 fixture regressions, fixture XCUITest, semantic accessibility, privacy, XPC interruption, UI smoke, performance, and reopen recovery; protected full status requires the complete changed-head rerun |
| 5. Profiles and Focus | Lead | Implemented locally; system execution pending | M3–4 | configured app-group store, bounded import, generation-checked workspace/layout/presentation history and rollback, atomic crash-recovery authority envelope, exact-target promotion, original-state recovery, unrelated-state preservation, durable Focus journal, and conservative display reconnect; real Focus/Shortcuts requires signed runtime |
| 6. Search and on-device interpretation | Lead | Complete for macOS 26 | M3–5 | collision-free opaque item identities, deterministic ranking, bounded and serialized latest-wins Spotlight replacement, cross-display metadata, 180 Core tests; macOS 27 tool remains gated |
| 7. UI and accessibility | Lead | Implemented; changed-head rerun pending | M3–6 | profile UI, fixture UI, and diagnostics review/save are implemented; fixture XCUITest and semantic accessibility passed on the immediately preceding candidate, while foreground Barline, VoiceOver, and Full Keyboard Access validation remain candidate-bound |
| 8. OS hardening | Lead | Implemented; changed-head runtime/macOS 27 pending | M3–7 | coordinate-safe display matching, categorized recovery diagnostics, configuration-derived Release probes, bounded XPC mutation deadlines, and privacy gates are implemented; the immediately preceding candidate passed XPC/UI/performance and all reopen-recovery cycles; changed-head evidence, physical scenario matrix, release soak, and macOS 27 remain pending |
| 9. Distribution readiness | Lead | Exact-head unsigned preflight pass; signed completion pending | M0–8 | exact-head unsigned archive topology, arm64 identity, and privacy-safe metadata pass; a prior source SHA passed Developer ID export, App Group profile validation, notarization, stapling, Gatekeeper, Sparkle signing, checksums, SBOM, and source archive, but current source requires regeneration after the full-gate prerequisite and before clean install/update |

## External boundaries currently known

- Xcode 27 beta 6 / Swift 6.4 is not installed.
- No macOS 27 runtime host is available, so runtime compatibility cannot be claimed.
- The canonical `Mabry-Ventures/Barline` repository, `origin`, protected ruleset,
  and pull request exist; the protected local macOS check remains pending until
  the complete foreground full gate passes for the changed candidate SHA.
- A valid Mabry Ventures Developer ID identity and Barline App Group
  provisioning profiles exist locally. Keychain authorization is configured,
  and a Developer ID export has passed nested signature validation.
- Sparkle signing material and the full credentialed release path passed on a
  prior source SHA. The `barline-notary` Keychain profile is currently absent,
  so exact-head notarization requires restoring that external credential.
- Developer Tools automation mode and the fixture accessibility path have been
  validated. The production reopen-to-visible p95 gate necessarily activates
  Barline and requires a dedicated unlocked interactive session.

The lead owns all project-file, scheme, test-plan, configuration, entitlement,
identifier, dependency, and integration changes. Delegated audits are advisory
until their findings are incorporated and rerun by the lead.
