# Test matrix

This is a status ledger, not release evidence. Exact candidate results belong
under ignored `.artifacts/ci/<sha>/` directories.

| Area | Current automated evidence | Status |
| --- | --- | --- |
| Pure domain | Swift Testing for snapshots, state coordination, profile presentation, display reconnect resolution, persistence/import, search, Spotlight records, and command/service validation | 174 tests pass on the latest clean candidate with 96.16% line coverage |
| Recovery policy | Standalone Swift script | Implemented |
| Notch overflow resolver | Standalone Swift script | Implemented |
| Debug/Release/analyze | Local Xcode steps in `script/ci.sh full` | Passed on the preceding source SHA; current-head full rerun required |
| Architecture firewall | Static boundary script | Implemented and passing |
| Fixture regression | Script runs snapshot/state/profile/command cases and launches a configurable three-status-item app | 128 regressions passed on the preceding source SHA; current-head full rerun required |
| Fixture app | Environment-configurable status items plus deterministic accessibility surface | Implemented as `BarlineFixture` |
| XPC interruption | Local kill/relaunch probe | 100 production reopen requests and eight helper replacements passed on a prior candidate; current foreground rerun required |
| UI smoke | Exact-build visible-status-item probe plus compiled XCUITest target | Latest fixture XCUITest did not activate the background fixture; production status-item smoke requires a focus-approved session |
| Accessibility | Source assertions and fixture runtime AX label audit | Latest semantic fixture audit is blocked because the invoking process lacks Accessibility trust; manual VoiceOver and Full Keyboard Access remain required |
| Support-bundle privacy | Encoder content probes plus static logging/credential checks | Passes on the latest clean candidate |
| Performance smoke | Shelf responsiveness and app-owned production reopen probes | Presentation and compatibility-recovery metrics are separated; foreground exact-head measurement requires a focus-approved session |
| Soak | Repeated Core cycles plus XPC interruption and responsiveness | Prior 10-cycle integration pass; exact-candidate release-duration soak remains required |
| Release/install/update | Clean archive, signing, notarization, stapling, Gatekeeper, Sparkle, and SBOM gates | Exact-head unsigned topology/privacy preflight passes; signed packaging/notarization passed only on a prior SHA and must be regenerated after restoring the notary profile; integrated full/release summary plus clean install/update validation remain required |

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
