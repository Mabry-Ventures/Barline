# Barline execution plan

This is the live implementation ledger. A milestone is complete only when its
code and evidence match the build specification; documentation alone is not a
gate result.

| Milestone | Owner | Status | Dependencies | Evidence |
| --- | --- | --- | --- | --- |
| 0. Import and provenance | Lead; delegated audit | Complete | none | Exact history, remotes, ancestor proof, vendor tag, license/provenance records |
| 1. Baseline build and audit | Lead; delegated audits | Complete | M0 | Debug/Release/analyze/archive and policy scripts pass; permission-gated launch; result bundles |
| 2. Rebrand and build system | Lead | Complete | M1 | Debug/Release/analyze pass; strict lint 0 violations; canonical Run verification pass |
| 3. Core and compatibility firewall | Lead | Complete | M2 | 167 Core tests; strict source/binary firewall; helper generation rebasing, durable authority rehydration, and fail-closed recovery |
| 4. Fixture and local CI | Lead; delegated validation | Implemented; new exact-head rerun pending | M3 | real fixture/test targets and test plan; prior exact-head XCUITest passed without launching Barline; source changes require regeneration |
| 5. Profiles and Focus | Lead | Implemented locally; system execution pending | M3–4 | configured app-group store, bounded import, transactional workspace/layout/presentation state, durable authority and Focus journals, conservative display reconnect; real Focus/Shortcuts requires signed runtime |
| 6. Search and on-device interpretation | Lead | Complete for macOS 26 | M3–5 | collision-free opaque item identities, deterministic ranking, bounded Spotlight synchronization, cross-display metadata, 167 Core tests; macOS 27 tool remains gated |
| 7. UI and accessibility | Lead | Prior candidate passed; new exact-head rerun pending | M3–6 | profile UI, fixture UI, diagnostics review/save, and semantic accessibility audit; foreground Barline validation is excluded by the operator focus constraint |
| 8. OS hardening | Lead | Non-focus integration implemented; new exact candidate/macOS 27 pending | M3–7 | coordinate-safe display matching, categorized recovery diagnostics, and privacy gates; reopen samples now reset to a hidden Settings baseline, but foreground reopen-to-visible p95 requires a dedicated session or host; Xcode/macOS 27 unavailable |
| 9. Distribution readiness | Lead | Prior candidate notarized; new exact-head evidence pending | M0–8 | prior exact candidate passed Developer ID export, notarization, stapling, Gatekeeper, Sparkle signing, and SBOM; identity is configuration-driven; all evidence must be regenerated after source changes |

## External boundaries currently known

- Xcode 27 beta 6 / Swift 6.4 is not installed.
- No macOS 27 runtime host is available, so runtime compatibility cannot be claimed.
- The canonical `Mabry-Ventures/Barline` repository, `origin`, protected ruleset,
  and pull request exist; the protected local macOS check remains red at the
  host-permission boundaries below.
- A valid Mabry Ventures Developer ID identity and Barline App Group
  provisioning profiles exist locally. Keychain authorization is configured,
  and a Developer ID export has passed nested signature validation.
- The local notary profile and Sparkle signing material are available and passed
  on the prior candidate; the new exact head must repeat the distribution gate.
- Developer Tools automation mode is enabled. Fixture XCUITest can run without
  focusing Barline, but the production reopen-to-visible p95 gate necessarily
  activates Barline and remains blocked by the operator's no-focus constraint.

The lead owns all project-file, scheme, test-plan, configuration, entitlement,
identifier, dependency, and integration changes. Delegated audits are advisory
until their findings are incorporated and rerun by the lead.
