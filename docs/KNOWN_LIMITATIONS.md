# Known limitations

This list describes the active development tree. It is not a release claim.

## Product

- Profile storage, capture, transactional activation, deletion, Presentation
  templates, source precedence, App Intents and Focus bridging are wired. Full
  groups/spacers editing, Ice-import UI, display reconnect reconciliation,
  user-facing recovery controls, and complete undo/redo remain absent.
- Real Focus and Shortcuts execution is not proven without a provisioned signed
  build; the local development certificate is unavailable.
- Deterministic search and bounded Spotlight indexing are connected. Foundation
  Models typed parsing/inference and macOS 27 `SpotlightSearchTool` are absent.
- Missing required Accessibility permission still routes launch to a permissions
  window rather than allowing the complete degraded product experience.

## Compatibility and quality

- The strict XPC compatibility firewall is complete and passing; private
  symbols remain isolated inside the helper.
- Fixture, unit, integration and UI targets plus an explicit test plan exist.
  UI execution is administrator-blocked because Developer Tools automation mode
  is disabled on this host.
- The status-item smoke, bounded shelf-responsiveness probe, and 10-cycle Core/
  XPC/shelf soak pass locally. Full XCUITest, AX/VoiceOver, display, sleep/wake,
  permission-revocation, representative-hardware, and 30-minute soak matrices
  have not passed.
- Xcode 27 is not installed and no macOS 27 runtime host has been used.

## Distribution

- The unsigned release dry-run script exists. No signed candidate, notarization,
  stapling, Gatekeeper proof, SBOM, or clean install/update evidence exists.
- Sparkle is embedded but disabled. There is no Barline feed, public key,
  appcast, or signed update test.
- The canonical `origin`, public support URLs, and GitHub branch rules are not
  configured.

Track candidate-specific results in [the test matrix](TEST_MATRIX.md), release
requirements in [RELEASING.md](RELEASING.md), and architecture progress in
[COMPATIBILITY_FIREWALL_STATUS.md](COMPATIBILITY_FIREWALL_STATUS.md).
