# Barline execution plan

This is the live implementation ledger. A milestone is complete only when its
code and evidence match the build specification; documentation alone is not a
gate result.

| Milestone | Owner | Status | Dependencies | Evidence |
| --- | --- | --- | --- | --- |
| 0. Import and provenance | Lead; delegated audit | Complete | none | Exact history, remotes, ancestor proof, vendor tag, license/provenance records |
| 1. Baseline build and audit | Lead; delegated audits | Complete | M0 | Debug/Release/analyze/archive and policy scripts pass; permission-gated launch; result bundles |
| 2. Rebrand and build system | Lead | Complete | M1 | Debug/Release/analyze pass; strict lint 0 violations; canonical Run verification pass |
| 3. Core and compatibility firewall | Lead | In progress | M2 | Core tests, XPC probes/interruption/recovery, private-boundary scan |
| 4. Fixture and local CI | Lead; delegated validation | Pending | M3 | fast/full gates, fixture suite, Linux hygiene |
| 5. Profiles and Focus | Lead | Pending | M3–4 | migration, activation/rollback, intents and Focus tests |
| 6. Search and on-device interpretation | Lead | Pending | M3–5 | ranking, Spotlight, validator and evaluation tests |
| 7. UI and accessibility | Lead | Pending | M3–6 | keyboard/UI/a11y gates and visual modes |
| 8. OS hardening | Lead | Pending | M3–7 | macOS 26 matrix, performance/soak, Xcode 27 status |
| 9. Distribution readiness | Lead | Pending | M0–8 | archive/release dry run, credential-bound proof, GPL package |

## External boundaries currently known

- Xcode 27 beta 6 / Swift 6.4 is not installed.
- No macOS 27 runtime host is available, so runtime compatibility cannot be claimed.
- A matching local Mac Development certificate for the observed development team is unavailable.
- The target has no configured `origin`; GitHub status publishing, rulesets, and repository settings require the future Barline GitHub repository and administration rights.
- Developer ID and Apple Distribution identities exist locally, but notarization and Sparkle credentials have not been assumed or used.

The lead owns all project-file, scheme, test-plan, configuration, entitlement,
identifier, dependency, and integration changes. Delegated audits are advisory
until their findings are incorporated and rerun by the lead.
