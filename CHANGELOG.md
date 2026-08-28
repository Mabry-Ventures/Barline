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
- Core Spotlight indexing and runtime capability probes for Spotlight and
  Foundation Models; these adapters are not yet connected to the app search UI.
- Compatibility contracts and an XPC-oriented backend migration in progress.
- Linux-only repository-hygiene workflow and fail-closed local CI command
  surface.

### Changed

- Minimum deployment target is macOS 26.0 and shipping builds are intended for
  Apple Silicon only.
- Product-facing Ice names and identifiers were replaced with Barline; Ice
  remains in provenance, attribution, historical migration keys, and historical
  documentation where necessary.

### Known incomplete work

- Profile persistence exists as a tested domain component but is not connected
  to an app storage location or exposed in the app UI.
- Focus Filters, App Intents, Foundation Models inference, the fixture app,
  complete scenario matrix, support-bundle export, and local release
  automation are not implemented.
- Signing, notarization, Sparkle updates, clean installation/update testing, and
  macOS 27 runtime validation have not been completed.
