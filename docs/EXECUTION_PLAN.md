# Barline execution plan

This is the live implementation ledger. A milestone is complete only when its
code and evidence match the build specification; documentation alone is not a
gate result.

| Milestone | Owner | Status | Dependencies | Evidence |
| --- | --- | --- | --- | --- |
| 0. Import and provenance | Lead; delegated audit | Complete | none | Exact history, remotes, ancestor proof, vendor tag, license/provenance records |
| 1. Baseline build and audit | Lead; delegated audits | Complete | M0 | Debug/Release/analyze/archive and policy scripts pass; permission-gated launch; result bundles |
| 2. Rebrand and build system | Lead | Complete | M1 | Debug/Release/analyze pass; strict lint 0 violations; canonical Run verification pass |
| 3. Core and compatibility firewall | Lead | Complete | M2 | 174 Core tests; strict source/binary firewall; helper generation rebasing, absolute mutation deadlines, session-cancellation quiescence, durable authority rehydration, and fail-closed recovery |
| 4. Fixture and local CI | Lead; delegated validation | Exact-candidate non-focus pass; full pending | M3 | fast and non-focus lanes pass with 174 Core and 128 fixture regressions, unit/integration execution, fixture XCUITest, semantic accessibility, and privacy checks; protected full status still requires production runtime gates |
| 5. Profiles and Focus | Lead | Implemented locally; system execution pending | M3–4 | configured app-group store, bounded import, generation-checked workspace/layout/presentation history and rollback, stale-publication rejection, durable authority and Focus journals, conservative display reconnect; real Focus/Shortcuts requires signed runtime |
| 6. Search and on-device interpretation | Lead | Complete for macOS 26 | M3–5 | collision-free opaque item identities, deterministic ranking, bounded Spotlight synchronization, cross-display metadata, 174 Core tests; macOS 27 tool remains gated |
| 7. UI and accessibility | Lead | Exact-candidate fixture pass; foreground/manual pass pending | M3–6 | profile UI, fixture UI, diagnostics review/save, fixture XCUITest, and semantic accessibility pass; foreground Barline, VoiceOver, and Full Keyboard Access validation remain candidate-bound |
| 8. OS hardening | Lead | Non-focus candidate pass; foreground/macOS 27 pending | M3–7 | coordinate-safe display matching, categorized recovery diagnostics, configuration-derived Release probes, bounded XPC mutation deadlines, and privacy gates pass without production activation; generation/PID-bound foreground presentation, physical scenario matrix, release soak, and macOS 27 remain pending |
| 9. Distribution readiness | Lead | Signed candidate pass; integrated release completion pending | M0–8 | clean candidate passed Developer ID export, App Group profile validation, notarization, stapling, Gatekeeper, Sparkle signing, checksums, SBOM, and source archive; full-gate prerequisite plus clean install/update remain open and source changes require regeneration |

## External boundaries currently known

- Xcode 27 beta 6 / Swift 6.4 is not installed.
- No macOS 27 runtime host is available, so runtime compatibility cannot be claimed.
- The canonical `Mabry-Ventures/Barline` repository, `origin`, protected ruleset,
  and pull request exist; the protected local macOS check remains pending until
  the complete foreground full gate passes for the current SHA.
- A valid Mabry Ventures Developer ID identity and Barline App Group
  provisioning profiles exist locally. Keychain authorization is configured,
  and a Developer ID export has passed nested signature validation.
- The local notary profile and Sparkle signing material are available and passed
  on the latest clean candidate; every source change must repeat the distribution
  gate.
- Developer Tools automation mode is enabled. Fixture XCUITest can run without
  focusing Barline, but the production reopen-to-visible p95 gate necessarily
  activates Barline and requires a dedicated interactive session that will not
  disrupt the operator's active desktop.

The lead owns all project-file, scheme, test-plan, configuration, entitlement,
identifier, dependency, and integration changes. Delegated audits are advisory
until their findings are incorporated and rerun by the lead.
