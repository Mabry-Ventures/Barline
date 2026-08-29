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
| 7. UI and accessibility | Lead | Accessibility pass; XCUITest execution pending | M3–6 | profile UI, fixture UI, diagnostics review/save, visible-window status-item smoke, and semantic accessibility audit pass; Developer Tools automation remains disabled |
| 8. OS hardening | Lead | Interactive integration pass; exact candidate/macOS 27 pending | M3–7 | Debug/Release runtime smoke, 100-request production reopen burst, eight helper replacements, privacy, and performance pass during integration; exact-head full/soak rerun required; Xcode/macOS 27 unavailable |
| 9. Distribution readiness | Lead | Profiles installed; signed archive authorization pending | M0–8 | canonical repository, protected PR, exact-head unsigned archive/topology/GPL checks; App Group profiles installed; Keychain signing authorization, notarization credentials, and Sparkle publication pending |

## External boundaries currently known

- Xcode 27 beta 6 / Swift 6.4 is not installed.
- No macOS 27 runtime host is available, so runtime compatibility cannot be claimed.
- The canonical `Mabry-Ventures/Barline` repository, `origin`, protected ruleset,
  and pull request exist; the protected local macOS check remains red at the
  host-permission boundaries below.
- A valid Mabry Ventures Developer ID identity and Barline App Group
  provisioning profiles exist locally. The signing private key still requires
  one-time local Keychain authorization before a signed archive can complete.
- No `barline-notary` Keychain profile is currently available. Sparkle trust
  material exists locally, but notarization credentials and the signed artifact
  are still required before feed publication.
- Developer Tools automation mode is disabled; enabling it requires administrator authorization, so the compiled XCUITest target cannot execute on this host.

The lead owns all project-file, scheme, test-plan, configuration, entitlement,
identifier, dependency, and integration changes. Delegated audits are advisory
until their findings are incorporated and rerun by the lead.
