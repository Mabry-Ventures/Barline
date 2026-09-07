# Changelog

## 1.0.9 (build 16)

- Bind delayed rehide work to its originating presentation, so an old click,
  hover, or timer cannot dismiss a newer shelf.
- Give the primary control window exclusive ownership of its clicks and use
  captured event coordinates for empty-space click arbitration.

- Restore temporarily revealed items to their original section/display even if
  neighboring icons disappear or move.
- Resolve hidden items' logical display ownership independently of their
  off-screen coordinates before activation or restoration.
- Preserve interrupted restoration across restarts and expose Retry Item
  Restoration in Layouts & Focus. Pause after three unsuccessful attempts.
- Keep pending restoration intact when a competing layout operation cannot
  proceed safely.
- Require exact-candidate target-action, performance and helper-recovery receipts
  before installed qualification passes.
- Match macOS-hosted status-item geometry consistently in performance probes,
  with regression tests for the observed two-point source/host width difference.

Barline has not published a binary release. Changes below describe the active
development line and are not release certification.

## Unreleased

### 1.0.8 local candidate corrections

- Route shelf-item clicks through the macOS session event stream with ordered
  source-queue barriers; do not mistake direct-process receipt for activation.
- Keep temporarily revealed native items out of the shelf until restoration,
  without changing saved layout positions.
- Prevent picker presentation during reveal/restore and avoid automatically
  reopening it over an unconfirmed or delayed target interface.
- Verify physical display geometry before treating a hosted item as visible;
  a stale macOS on-screen flag can otherwise skip reveal and click off-display.

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
- A General setting that keeps Barline out of the Dock even while its Settings
  window is open.
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
- Apple's Focus settings now select any saved Barline Profile directly instead
  of enabling a Barline-specific Presentation mode. Profile and Focus changes
  serialize layout, workspace settings, and resolved group/spacer presentation
  as one verified transaction, retain a crash-stable pre-Focus journal, and
  clear authority when rollback or a restored profile definition cannot be
  proven current.
- Menu-bar restoration now uses global cross-display planning, section-relative
  postconditions, explicit stable destination-display targeting,
  already-correct no-op handling, and monotonic helper generation rebasing.
- The hidden-item shelf now keeps a valid AppKit presentation ordered while an
  unrelated compatibility-helper request delays WindowServer observation.
  Helper confirmation remains stronger evidence and recovery input, but helper
  availability can no longer erase a delivered status-item click.
- Background launch no longer opens permission or Settings windows from a
  transient permission read; permission UI remains contextual.
- Release evidence now preserves a strict build-metadata whitelist instead of
  raw Xcode settings containing machine paths or signing configuration.

### Release boundaries

- Real Focus/Shortcuts, VoiceOver, display/sleep-wake, signed installation, and
  update-from-previous execution require candidate-bound system testing.
- Developer ID signing, Barline App Group provisioning, notarization, stapling,
  Gatekeeper, Sparkle signing, and Developer Tools automation have passed on a
  clean candidate and must be repeated after source changes.
- Foreground production runtime validation requires a dedicated interactive
  session where Barline focus changes are acceptable. Xcode 27 and a macOS 27
  runtime host remain unavailable, so no macOS 27 runtime claim is made.
