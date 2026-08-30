# Test matrix

This is a status ledger, not release evidence. Exact candidate results belong
under ignored `.artifacts/ci/<sha>/` directories.

| Area | Current automated evidence | Status |
| --- | --- | --- |
| Pure domain | Swift Testing for snapshots, state coordination, profile presentation, display reconnect resolution, persistence/import, search, Spotlight records, and command/service validation | 180 tests pass on the exact-head full gate with 96.26% line coverage |
| Recovery policy | Standalone Swift script | Implemented |
| Notch overflow resolver | Standalone Swift script | Implemented |
| Debug/Release/analyze | Local Xcode steps in `script/ci.sh full` | Exact-head full gate passes on macOS 26.6.2 arm64 |
| Architecture firewall | Static boundary script | Implemented and passing |
| Fixture regression | Script runs snapshot/state/profile/command cases and launches a configurable three-status-item app | 134 regressions pass on the exact-head full gate |
| Fixture app | Environment-configurable status items plus deterministic accessibility surface | Implemented as `BarlineFixture` |
| XPC interruption | Local kill/relaunch probe | Exact-head full gate passes the replacement-helper probe and eight helper-interruption/reopen cycles |
| UI smoke | Exact-build visible-status-item probe plus compiled XCUITest target | Exact-head fixture XCUITest and production visible-window smoke pass in the unlocked interactive session |
| Accessibility | Source assertions and fixture runtime AX label audit | Exact-head semantic fixture audit passes; manual VoiceOver and Full Keyboard Access remain required |
| Support-bundle privacy | Encoder content probes plus static logging/credential checks | Passes on the exact-head full gate |
| Performance smoke | Shelf responsiveness and app-owned production reopen probes | Exact-head 20-cycle performance and 100-cycle reopen-burst presentation budgets pass in the unlocked interactive session |
| Soak | Repeated Core cycles plus XPC interruption and responsiveness | Prior 10-cycle integration pass; exact-candidate release-duration soak remains required |
| Release/install/update | Clean archive, signing, notarization, stapling, Gatekeeper, Sparkle, and SBOM gates | Exact-head unsigned topology/privacy preflight passes; signed packaging/notarization still requires the external `barline-notary` profile; clean install/update validation remains required |

The fail-closed full gate runs these scripts and reports unavailable permissions
or missing product behavior instead of silently treating them as passed.

## Required real-macOS scenarios

No complete runtime pass has been recorded for clean install, upgrade, Ice import,
login launch, sleep/wake, repeated sleep/wake, active-space changes, full-screen,
Stage Manager, menu bar auto-hide, display connect/disconnect, scaling changes,
notched/non-notched displays, single/multiple displays, mixed scaling,
permission deny/grant/revoke, active-profile app relaunch, Focus, App Intent,
model availability, Spotlight reindex, XPC interruption, incomplete snapshots,
menu tracking, activation rollback, or last-known-good restore.

Headless Core coverage proves deterministic display alias resolution,
ambiguity rejection, live-ID mutation targeting, profile schema v7 migration,
transactional resolved presentation, and group/spacer projection. It does not
replace the required physical display connect/disconnect runtime pass.

macOS 27 runtime compatibility cannot be claimed without a macOS 27 host. The
current host documented in the baseline audit has Xcode 26.6 only.
