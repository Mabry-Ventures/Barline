# Barline execution plan

This is the live implementation ledger. A milestone is complete only when its
code and evidence match the build specification; documentation alone is not a
gate result.

| Milestone | Owner | Status | Dependencies | Evidence |
| --- | --- | --- | --- | --- |
| 0. Import and provenance | Lead; delegated audit | Complete | none | Exact history, remotes, ancestor proof, vendor tag, license/provenance records |
| 1. Baseline build and audit | Lead; delegated audits | Complete | M0 | Debug/Release/analyze/archive and policy scripts pass; permission-gated launch; result bundles |
| 2. Rebrand and build system | Lead | Complete | M1 | Debug/Release/analyze pass; strict lint 0 violations; canonical Run verification pass |
| 3. Core and compatibility firewall | Lead | Complete | M2 | 96 Core tests; strict source/binary firewall; signed helper kill/relaunch recovery |
| 4. Fixture and local CI | Lead; delegated validation | Implemented; XCUITest execution blocked | M3 | real fixture/test targets and test plan; unit/integration pass; automation mode needs administrator authorization |
| 5. Profiles and Focus | Lead | Implemented locally; system execution pending | M3–4 | app-group store, transactional activation, precedence, extension metadata; real Focus/Shortcuts requires signed runtime |
| 6. Search and on-device interpretation | Lead | Complete for macOS 26 | M3–5 | deterministic panel ranking, bounded Spotlight synchronization, 96 Core tests; macOS 27 tool remains gated |
| 7. UI and accessibility | Lead | Implemented; credentialed/manual passes pending | M3–6 | profile UI, fixture UI, diagnostics review/save, status-item smoke pass; AX/XCUITest/VoiceOver boundaries recorded |
| 8. OS hardening | Lead | Complete on available macOS 26 host; macOS 27 blocked | M3–7 | build/analyze, 10-cycle soak, helper interruption, and 20/20 shelf responsiveness pass; Xcode/macOS 27 unavailable |
| 9. Distribution readiness | Lead | Dry-run implemented; externally blocked | M0–8 | unsigned archive/topology/GPL checks; signing, notarization, Sparkle and GitHub administration pending |

## External boundaries currently known

- Xcode 27 beta 6 / Swift 6.4 is not installed.
- No macOS 27 runtime host is available, so runtime compatibility cannot be claimed.
- A matching local Mac Development certificate for the observed development team is unavailable.
- The target has no configured `origin`; GitHub status publishing, rulesets, and repository settings require the future Barline GitHub repository and administration rights.
- Developer ID and Apple Distribution identities exist locally, but notarization and Sparkle credentials have not been assumed or used.
- Developer Tools automation mode is disabled; enabling it requires administrator authorization, so the compiled XCUITest target cannot execute on this host.
- The invoking host is trusted for basic Accessibility access but does not expose the fixture window through `AXWindows`; the runtime semantic audit therefore reports unavailable rather than claiming a pass.

The lead owns all project-file, scheme, test-plan, configuration, entitlement,
identifier, dependency, and integration changes. Delegated audits are advisory
until their findings are incorporated and rerun by the lead.
