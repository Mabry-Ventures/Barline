# Barline execution plan

This is the live implementation ledger. A milestone is complete only when its
code and evidence match the build specification; documentation alone is not a
gate result.

| Milestone | Owner | Status | Dependencies | Evidence |
| --- | --- | --- | --- | --- |
| 0. Import and provenance | Lead; delegated audit | Complete | none | Exact history, remotes, ancestor proof, vendor tag, license/provenance records |
| 1. Baseline build and audit | Lead; delegated audits | Complete | M0 | Debug/Release/analyze/archive and policy scripts pass; permission-gated launch; result bundles |
| 2. Rebrand and build system | Lead | Complete | M1 | Debug/Release/analyze pass; strict lint 0 violations; canonical Run verification pass |
| 3. Core and compatibility firewall | Lead | Complete | M2 | 164 Core tests; strict source/binary firewall; helper generation rebasing and fail-closed recovery |
| 4. Fixture and local CI | Lead; delegated validation | Implemented; XCUITest execution blocked | M3 | real fixture/test targets and test plan; unit/integration pass; automation mode needs administrator authorization |
| 5. Profiles and Focus | Lead | Implemented locally; system execution pending | M3–4 | app-group store, atomic workspace/layout/presentation transactions, display reconnect aliases, operational groups/spacers, durable Focus journal, serialized activation/history, extension metadata; real Focus/Shortcuts requires signed runtime |
| 6. Search and on-device interpretation | Lead | Complete for macOS 26 | M3–5 | deterministic panel ranking, bounded Spotlight synchronization, cross-display metadata, 164 Core tests; macOS 27 tool remains gated |
| 7. UI and accessibility | Lead | Implemented; credentialed/manual passes pending | M3–6 | profile UI, fixture UI, diagnostics review/save, status-item smoke pass; AX/XCUITest/VoiceOver boundaries recorded |
| 8. OS hardening | Lead | Headless exact pass; interactive/macOS 27 blocked | M3–7 | exact-head Debug, analyze, and test-plan compilation pass; runtime/soak gates remain unavailable on this host; Xcode/macOS 27 unavailable |
| 9. Distribution readiness | Lead | Exact unsigned dry-run passes; externally blocked | M0–8 | canonical repository, protected PR, exact-head unsigned archive/topology/GPL checks; App Group profiles, notarization, and Sparkle publication pending |

## External boundaries currently known

- Xcode 27 beta 6 / Swift 6.4 is not installed.
- No macOS 27 runtime host is available, so runtime compatibility cannot be claimed.
- The canonical `Mabry-Ventures/Barline` repository, `origin`, protected ruleset,
  and pull request exist; the protected local macOS check remains red at the
  host-permission boundaries below.
- A valid Mabry Ventures Developer ID identity exists, but Barline App Group
  provisioning profiles and a connected Xcode Apple account are unavailable.
- A notarization Keychain profile is available. Sparkle trust material also
  exists locally, but missing App Group provisioning prevents creation of the
  signed artifact required before notarization and feed publication.
- Developer Tools automation mode is disabled; enabling it requires administrator authorization, so the compiled XCUITest target cannot execute on this host.
- The invoking host has not been granted the Accessibility TCC permission
  required by the runtime semantic audit.

The lead owns all project-file, scheme, test-plan, configuration, entitlement,
identifier, dependency, and integration changes. Delegated audits are advisory
until their findings are incorporated and rerun by the lead.
