# Test matrix

This is a status ledger, not release evidence. Exact candidate results belong
under ignored `.artifacts/ci/<sha>/` directories.

| Area | Current automated evidence | Status |
| --- | --- | --- |
| Pure domain | Swift Testing for snapshots, state coordination, profiles, persistence/import, search, Spotlight records, and command/service validation | 83 tests passed locally on 2026-08-28; rerun required after integration changes |
| Recovery policy | Standalone Swift script | Implemented |
| Notch overflow resolver | Standalone Swift script | Implemented |
| Debug/Release/analyze | Local Xcode steps in `script/ci.sh full` | Implemented command surface |
| Architecture firewall | Static boundary script | Implemented; known migration violations remain |
| Fixture regression | Script runs 20+ snapshot/state/profile/command cases | Implemented; this is not the required fixture app |
| Fixture app | Controllable status-item helper | Missing |
| XPC interruption | Local kill/relaunch probe | Implemented; no current passing evidence recorded |
| UI smoke | Exact-build launch/window probe | Implemented; no Xcode UI target or interaction suite |
| Accessibility | Source assertions and runtime AX label audit | Implemented; permission-bound and not a manual VoiceOver pass |
| Support-bundle privacy | Static logging/credential check | Failed locally: exporter absent and relaunch logging path flagged |
| Performance smoke | Shelf responsiveness probe | Implemented; no candidate result recorded |
| Soak | Bounded repeated-cycle harness | Missing |
| Release/install/update | Local release gate | Missing |

The fail-closed full gate runs these scripts and reports unavailable permissions
or missing product behavior instead of silently treating them as passed.

## Required real-macOS scenarios

No complete pass has been recorded for clean install, upgrade, Ice import,
login launch, sleep/wake, repeated sleep/wake, active-space changes, full-screen,
Stage Manager, menu bar auto-hide, display connect/disconnect, scaling changes,
notched/non-notched displays, single/multiple displays, mixed scaling,
permission deny/grant/revoke, active-profile app relaunch, Focus, App Intent,
model availability, Spotlight reindex, XPC interruption, incomplete snapshots,
menu tracking, activation rollback, or last-known-good restore.

macOS 27 runtime compatibility cannot be claimed without a macOS 27 host. The
current host documented in the baseline audit has Xcode 26.6 only.
