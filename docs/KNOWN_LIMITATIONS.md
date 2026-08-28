# Known limitations

This list describes the active development tree. It is not a release claim.

## Product

- Profile schema, file persistence/recovery, Ice-import preview, and validators
  exist in `BarlineCore`, but no production storage location, transactional live
  activation, per-display reconciliation, groups/spacers UI, presentation UI,
  or Ice-import UI is wired into the app.
- Focus Filters and App Intents have no extension or runtime integration.
- The new deterministic search domain, Core Spotlight adapter, and runtime
  capability probes are not connected to the inherited search panel.
  Foundation Models typed parsing/inference is absent.
- Diagnostics, support-bundle export, user-facing safe recovery, and complete
  undo/redo are absent.
- Missing required Accessibility permission still routes launch to a permissions
  window rather than allowing the complete degraded product experience.

## Compatibility and quality

- The XPC compatibility firewall migration is incomplete; legacy private-symbol
  and raw-window-ID paths remain. The strict architecture check is expected to
  report violations until lead integration completes.
- There is no fixture app, Xcode unit/integration/UI target, or test plan. Pure
  `BarlineCore` tests, standalone compatibility tests, and local smoke scripts
  do not establish end-to-end correctness.
- Full UI, VoiceOver, display, sleep/wake, permission-revocation, performance,
  and soak matrices have not passed.
- Xcode 27 is not installed and no macOS 27 runtime host has been used.

## Distribution

- No release script, signed candidate, notarization, stapling, Gatekeeper proof,
  SBOM, or clean install/update evidence exists.
- Sparkle is embedded but disabled. There is no Barline feed, public key,
  appcast, or signed update test.
- The canonical `origin`, public support URLs, and GitHub branch rules are not
  configured.

Track candidate-specific results in [the test matrix](TEST_MATRIX.md), release
requirements in [RELEASING.md](RELEASING.md), and architecture progress in
[COMPATIBILITY_FIREWALL_STATUS.md](COMPATIBILITY_FIREWALL_STATUS.md).
