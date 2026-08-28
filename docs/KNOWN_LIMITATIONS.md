# Known limitations

This list describes the active development tree. It is not a release claim.

## Product

- Profile storage, capture, transactional activation, editing, archive import/
  export, Presentation templates, App Intents/Focus delivery, and recovery are
  wired, including explicit Ice import preview and bounded layout undo/redo.
  Active-display profile overrides resolve through the helper's stable display
  identity. Display reconnect reconciliation and runtime group/spacer placement
  remain incomplete.
- Real Focus and Shortcuts execution is not proven without a provisioned signed
  build; the local development certificate is unavailable.
- Deterministic search, bounded Spotlight indexing, and typed on-device model
  interpretation are connected. macOS 27 `SpotlightSearchTool` remains blocked
  on the unavailable Xcode/macOS 27 lane.

## Compatibility and quality

- The strict XPC compatibility firewall is complete and passing; private
  symbols remain isolated inside the helper.
- Fixture, unit, integration and UI targets plus an explicit test plan exist.
  UI execution is administrator-blocked because Developer Tools automation mode
  is disabled on this host.
- Status-item smoke, bounded shelf responsiveness, and resource-sampled soak
  automation exist. Full XCUITest, AX/VoiceOver, display, sleep/wake,
  permission-revocation, representative-hardware, and release-duration soak
  evidence have not passed on the exact launch SHA.
- Xcode 27 is not installed and no macOS 27 runtime host has been used.

## Distribution

- The release pipeline implements Developer ID, entitlement/profile,
  notarization, stapling, Gatekeeper, Sparkle, checksum, SBOM, and source-archive
  gates. It cannot complete without App Group profiles and a notary profile.
- Sparkle is enabled only in Release with Barline's public key and canonical
  GitHub appcast URL. No previous public Barline version exists for update proof.
- The canonical public repository exists. Protected rules and local status
  publication wait on a fully green exact-head candidate.

Track candidate-specific results in [the test matrix](TEST_MATRIX.md), release
requirements in [RELEASING.md](RELEASING.md), and architecture progress in
[COMPATIBILITY_FIREWALL_STATUS.md](COMPATIBILITY_FIREWALL_STATUS.md).
