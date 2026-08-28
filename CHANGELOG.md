# Changelog

Barline has not published a binary release. Changes below describe the active
development line and are not release certification.

## Unreleased

### Added

- Barline product identity, original temporary icon sources, centralized build
  configuration, provenance, GPL notices, and local build commands.
- `BarlineCore` foundations for stable item identity, snapshot validation,
  last-known-good state coordination, profile schema version 3, profile JSON
  migration/validation, atomic profile-file storage and recovery, deterministic
  search, Spotlight record bounds, and typed command validation.
- Core Spotlight indexing and a bounded typed Foundation Models interpreter
  connected behind deterministic validation and confirmation.
- Compatibility contracts and a strict XPC compatibility firewall.
- Saved profile editing/import/export, transactional activation, Focus and App
  Intent delivery, Presentation templates, and last-known-good recovery.
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
- Profile and Focus changes now serialize layout and workspace settings as one
  verified transaction, retain a crash-stable pre-Presentation journal, and
  clear authority when rollback or a restored profile definition cannot be
  proven current.
- Menu-bar restoration now uses global cross-display planning, section-relative
  postconditions, explicit stable destination-display targeting,
  already-correct no-op handling, and monotonic helper generation rebasing.

### Release boundaries

- Real Focus/Shortcuts, VoiceOver, display/sleep-wake, signed installation, and
  update-from-previous execution require candidate-bound system testing.
- App Group provisioning, notarization credentials, Developer Tools automation,
  host Accessibility trust, and macOS 27 runtime validation remain external.
