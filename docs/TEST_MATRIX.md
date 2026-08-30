# Test matrix

This is a status ledger, not release evidence. Exact candidate results belong
under ignored `.artifacts/ci/<sha>/` directories.

| Area | Current automated evidence | Status |
| --- | --- | --- |
| Pure domain | Swift Testing for snapshots, state coordination, profile presentation, display reconnect resolution, persistence/import, search, Spotlight records, and command/service validation | 174 tests pass in integration; clean exact-head rerun required |
| Recovery policy | Standalone Swift script | Implemented |
| Notch overflow resolver | Standalone Swift script | Implemented |
| Debug/Release/analyze | Local Xcode steps in `script/ci.sh full` | Exact-head headless build/analyze and test-plan compilation pass |
| Architecture firewall | Static boundary script | Implemented and passing |
| Fixture regression | Script runs 20+ snapshot/state/profile/command cases and launches a configurable three-status-item app | Implemented |
| Fixture app | Environment-configurable status items plus deterministic accessibility surface | Implemented as `BarlineFixture` |
| XPC interruption | Local kill/relaunch probe | 100 production reopen requests and eight helper replacements pass in integration; clean exact-head rerun required |
| UI smoke | Exact-build visible-status-item probe plus compiled XCUITest target | Fixture XCUITest passes in integration without production activation; production status-item smoke requires a focus-approved session |
| Accessibility | Source assertions and fixture runtime AX label audit | Semantic fixture runtime audit passes in integration; clean exact-head rerun required |
| Support-bundle privacy | Encoder content probes plus static logging/credential checks | Implemented and previously passing; exact-head rerun required |
| Performance smoke | Shelf responsiveness and app-owned production reopen probes | Presentation and compatibility-recovery metrics are separated; foreground exact-head measurement requires a focus-approved session |
| Soak | Repeated Core cycles plus XPC interruption and responsiveness | Integration 10-cycle pass; clean exact-head rerun required |
| Release/install/update | Clean archive, signing, notarization, stapling, Gatekeeper, Sparkle, and SBOM gates | Prior candidate passed signed notarization; clean exact-head regeneration and install/update validation remain required |

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
