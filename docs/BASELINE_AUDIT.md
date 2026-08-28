# Imported baseline audit

## Candidate and environment

- Source: `79654cd8c249e2a1465a262cfda7175346fe7772`
- Vendor tag: `vendor/ice-0.11.13-macos26.4`
- Date: 2026-08-28
- Host: Apple Silicon MacBook Pro (`Mac17,6`, Apple M5 Max, 128 GB)
- Architecture: arm64
- macOS: 26.6.2 (25G83)
- Xcode: 26.6 (17F113)
- Swift: 6.3.3
- SDK used by Xcode: macOS 26.5

Apple's current toolchain matrix identifies Xcode 26.6 with Swift 6.3 as the
production lane and Xcode 27 beta 6 with Swift 6.4 as the compatibility lane.
Only Xcode 26.6 is installed on this host.

## Commands and results

Dependencies were resolved from the committed `Package.resolved` into isolated
paths under `.artifacts/baseline/`. The exact commands used `Ice.xcodeproj`, the
`Ice` scheme, `platform=macOS,arch=arm64`, explicit
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, and repository-local
DerivedData/package directories.

| Gate | Configuration | Signing | Result |
| --- | --- | --- | --- |
| Package resolution | pinned graph | n/a | Pass |
| Build | Debug arm64 | disabled | Pass |
| Build | Release arm64 | disabled | Pass |
| Static analysis | Debug arm64 | disabled | Pass |
| Archive topology | Release arm64 | disabled | Pass; app and XPC are thin arm64 under the explicit override |
| Recovery policy script | pure Swift | n/a | Pass |
| Notch overflow script | pure Swift | n/a | Pass |
| Release configuration validator | shell | n/a | Pass |
| SwiftLint strict | 106 Swift files | n/a | Fail: seven legacy aspect-ratio violations |
| Xcode tests | `Ice` scheme | n/a | Not configured; `xcodebuild test` exits 66 |
| Runtime launch | Debug arm64 | ad hoc artifact | Pass to permissions window |
| Development signing | Debug arm64 | local Apple Development | Blocked: no matching Mac Development certificate for team `E896WB332K` |

Result bundles are local, ignored artifacts:

- `.artifacts/baseline/debug.xcresult`
- `.artifacts/baseline/release.xcresult`
- `.artifacts/baseline/analyze.xcresult`
- `.artifacts/baseline/debug-signed.xcresult`

## Runtime evidence

The app launched and exposed an accessibility-readable Permissions window. It
requested Accessibility and Screen Recording immediately and did not allow the
main UI to continue while both were denied. Neither permission was granted.
At the permission gate, the process showed a 43.6 MB physical footprint and a
44.3 MB peak during a short observation. This is not an idle-energy, soak, or
ordinary-use measurement.

The visible/hidden/always-hidden sections, reveal modes, auto-rehide, Ice Bar,
layout editor, search, hotkeys, appearance, sleep/wake, active-space changes,
and display changes were not exercised because the required OS privacy grants
were unavailable to this imported code identity. No claim is made for those
behaviors.

## Existing architecture

The project contains two targets: the `Ice` app and `MenuBarItemService` XPC.
The app embeds the helper. `@MainActor AppState` is the composition root, while
`MenuBarItemManager` owns most enumeration, mutation, event synthesis, cache,
and rehide behavior. The XPC helper only resolves source PIDs through
Accessibility; it is not a general compatibility firewall.

`Shared/Bridging/Shims.swift` declares 19 private symbols directly with
`@_silgen_name` (18 CGS symbols and `GetProcessForPID`). Shared sources compile
into both app and helper, and the app calls these APIs directly. Raw window IDs,
PIDs, geometry, and space IDs cross general state boundaries. Private symbol
resolution is not guarded by `dlopen`/`dlsym`.

The baseline uses five-second polling in several managers and one-second
permission checks. A move-verification loop can spin tightly. It has useful
partial protections—generation-aware cache work, cancellation-aware semaphore
logic, snapshot completeness policy, bounded PID cache—but no single
transactional state coordinator, last-known-good rollback, capability-probed
backends, or complete XPC interruption recovery.

## Dependencies

The committed graph pins AXSwift 0.3.2, CompactSlider 1.2.1, Ifrit 2.0.6,
LaunchAtLogin-Modern 1.1.0, and Sparkle 2.8.0. All direct dependencies use
permissive licenses compatible with GPLv3. Sparkle is linked but updates are
disabled. The user-visible acknowledgements PDF is stale relative to its RTF
source and still lists a removed Semaphore dependency.

## Platform, signing, and updates

- Deployment target: macOS 14.0
- Default architecture: universal assumptions remain
- Swift language version: 5.0
- App Sandbox: disabled
- Hardened Runtime: enabled
- Entitlement files: none
- App identifier: `com.lxy1992.Ice`
- XPC identifier: `com.lxy1992.Ice.MenuBarItemService`
- Upstream team: `L9USTT7J86`
- Sparkle feed/public key: none tracked; update manager disabled

These identities and settings are baseline facts, not approved Barline values.

## Tests and automation

There are no Xcode unit, integration, or UI test targets, and the shared scheme
contains no testables. Two pure Swift policy scripts and one release-
configuration shell validator pass. The imported GitHub workflow uses movable
action tags and path filters and lacks explicit permissions, timeout,
concurrency, and manual dispatch; it is not the required Barline hygiene gate.

## Known baseline limitations

- Immediate permission prompt conflicts with Barline's contextual-permission requirement.
- Private WindowServer and event operations are not isolated to the XPC helper.
- Deprecated `CGImage(windowListFromArrayScreenBounds:...)` produces a compiler warning.
- SwiftLint reports seven legacy SwiftUI aspect-ratio warnings.
- App Intents metadata extraction reports that no AppIntents dependency exists.
- Strict SwiftLint fails even though the non-strict Xcode phase allows the build.
- No local test suite establishes behavioral coverage.
- No Xcode 27 installation or macOS 27 runtime is available on this host.
