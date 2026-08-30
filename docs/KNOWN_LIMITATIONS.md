# Known limitations

This list describes the active development tree. It is not a release claim.

## Product

- Profile storage, capture, transactional activation, editing, archive import/
  export, Presentation templates, App Intents/Focus delivery, and recovery are
  wired, including explicit Ice import preview and bounded layout undo/redo.
  Active-display overrides resolve through exact live IDs or unique opaque
  hardware aliases after reconnect. Groups and spacers participate in
  transactional authority and render in the Barline shelf. Physical reconnect
  and ambiguous identical-display behavior still require candidate-bound
  runtime validation.
- A Developer ID candidate with matching Barline App Group provisioning profiles
  has been produced and notarized. Real Focus and Shortcuts activation remains
  unproven because it has not been exercised in a candidate-bound system pass.
- Deterministic search, bounded Spotlight indexing, and typed on-device model
  interpretation are connected. macOS 27 `SpotlightSearchTool` remains blocked
  on the unavailable Xcode/macOS 27 lane.

## Compatibility and quality

- The strict XPC compatibility firewall is complete and passing; private
  symbols remain isolated inside the helper.
- Fixture, unit, integration and UI targets plus an explicit test plan exist.
  Developer Tools automation is enabled, but the latest fixture XCUITest could
  not activate the background fixture and the semantic audit lacked current
  Accessibility trust. Production UI/reopen execution remains pending because
  it activates Barline on the operator's desktop.
- Status-item smoke, bounded shelf responsiveness, and resource-sampled soak
  automation exist. Full XCUITest, AX/VoiceOver, display, sleep/wake,
  permission-revocation, representative-hardware, and release-duration soak
  evidence have not passed on the exact launch SHA.
- Xcode 27 is not installed and no macOS 27 runtime host has been used.

## Distribution

- The release pipeline implements Developer ID, entitlement/profile,
  notarization, stapling, Gatekeeper, Sparkle, checksum, SBOM, and source-archive
  gates. A prior clean candidate passed the credentialed pipeline, but the
  current source SHA has only an unsigned topology/privacy preflight and the
  `barline-notary` Keychain profile must be restored before exact-head
  notarization.
- Sparkle is enabled only in Release with Barline's public key and canonical
  GitHub appcast URL. No previous public Barline version exists for update proof.
- The canonical public repository exists. Protected rules are active and the
  exact-head local status remains pending while required foreground runtime,
  physical-scenario, soak, and installation gates are incomplete.

Track candidate-specific results in [the test matrix](TEST_MATRIX.md), release
requirements in [RELEASING.md](RELEASING.md), and architecture progress in
[COMPATIBILITY_FIREWALL_STATUS.md](COMPATIBILITY_FIREWALL_STATUS.md).
