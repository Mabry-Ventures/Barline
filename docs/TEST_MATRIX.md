# Test matrix

This is a status ledger, not release evidence. Exact candidate results belong
under ignored `.artifacts/ci/<sha>/` directories.

| Area | Current automated evidence | Status |
| --- | --- | --- |
| Pure domain | Swift Testing for snapshots, state coordination, profile presentation, display reconnect resolution, persistence/import, search, Spotlight records, and command/service validation | 164 tests pass locally on 2026-08-28 |
| Recovery policy | Standalone Swift script | Implemented |
| Notch overflow resolver | Standalone Swift script | Implemented |
| Debug/Release/analyze | Local Xcode steps in `script/ci.sh full` | Exact-head headless build/analyze and test-plan compilation pass |
| Architecture firewall | Static boundary script | Implemented and passing |
| Fixture regression | Script runs 20+ snapshot/state/profile/command cases and launches a configurable three-status-item app | Implemented |
| Fixture app | Environment-configurable status items plus deterministic accessibility surface | Implemented as `BarlineFixture` |
| XPC interruption | Local kill/relaunch probe | 100 production reopen requests and eight helper replacements pass in integration; clean exact-head rerun required |
| UI smoke | Exact-build visible-status-item probe plus compiled XCUITest target | Status-item smoke passes; XCUITest execution blocked by disabled Developer Tools automation mode |
| Accessibility | Source assertions and fixture runtime AX label audit | Source/fixture build and on-screen fixture presentation pass; the host returns the application object through `AXWindows`, so the semantic runtime audit is unavailable |
| Support-bundle privacy | Encoder content probes plus static logging/credential checks | Implemented and previously passing; exact-head rerun required |
| Performance smoke | Shelf responsiveness and app-owned production reopen probes | Integration 100/100 reopen pass, 30.3 ms p95, 34.6 ms max, plus eight recovery cycles; clean exact-head rerun required |
| Soak | Repeated Core cycles plus XPC interruption and responsiveness | Integration 10-cycle pass; clean exact-head rerun required |
| Release/install/update | Clean unsigned archive/topology gate | Exact-head unsigned archive passes; signed install/update externally blocked |

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
