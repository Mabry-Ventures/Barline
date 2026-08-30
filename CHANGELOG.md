# Changelog

Barline has not published a binary release. Changes below describe the active
development line and are not release certification.

## Unreleased

### Added

- Barline product identity, original temporary icon sources, centralized build
  configuration, provenance, GPL notices, and local build commands.
- `BarlineCore` foundations for stable item identity, snapshot validation,
  last-known-good state coordination, profile schema version 7, profile JSON
  migration/validation with exact appearance checkpoints, atomic profile-file
  storage and recovery, deterministic
  search, Spotlight record bounds, and typed command validation.
- Core Spotlight indexing and a bounded typed Foundation Models interpreter
  connected behind deterministic validation and confirmation.
- Compatibility contracts and a strict XPC compatibility firewall.
- Saved profile editing/import/export, transactional activation, Focus and App
  Intent delivery, Presentation templates, opaque display reconnect aliases,
  operational shelf groups/spacers, and last-known-good recovery.
- Contextual permissions and degraded settings/search/diagnostics behavior.
- Privacy-safe reviewed support-bundle export and a deterministic fixture app.
- Release-only Sparkle trust configuration and credentialed packaging tooling.
- Linux-only repository-hygiene workflow and fail-closed local CI command
  surface.

### Changed

- Minimum deployment target is macOS 26.0 and shipping builds are intended for
  Apple Silicon only.
- Product-facing Ice names and identifiers were replaced with Barline; Ice
  remains in provenance, attribution, historical migration keys, and historical
  documentation where necessary.
- Profile and Focus changes now serialize layout, workspace settings, and
  resolved group/spacer presentation as one verified transaction, retain a
  crash-stable pre-Presentation journal, and clear authority when rollback or a
  restored profile definition cannot be proven current.
- Menu-bar restoration now uses global cross-display planning, section-relative
  postconditions, explicit stable destination-display targeting,
  already-correct no-op handling, and monotonic helper generation rebasing.

### Release boundaries

- Real Focus/Shortcuts, VoiceOver, display/sleep-wake, signed installation, and
  update-from-previous execution require candidate-bound system testing.
- Developer ID signing, Barline App Group provisioning, notarization, stapling,
  Gatekeeper, Sparkle signing, and Developer Tools automation have passed on a
  clean candidate and must be repeated after source changes.
- Foreground production runtime validation requires a dedicated interactive
  session where Barline focus changes are acceptable. Xcode 27 and a macOS 27
  runtime host remain unavailable, so no macOS 27 runtime claim is made.
