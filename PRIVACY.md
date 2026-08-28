# Privacy

Barline is a local macOS utility. It has no account, cloud service, analytics
SDK, advertising SDK, telemetry upload, or remote AI service. Barline does not
sell data or upload a menu bar inventory.

## Data Barline handles

Barline reads menu bar window metadata, application identifiers, item titles,
geometry, and process identifiers to identify and arrange status items. When
Screen Recording permission is granted, it captures menu bar item imagery for
local previews and appearance rendering. Those images are kept in process
memory; the current app does not provide an image-upload path.

Preferences, hotkeys, appearance choices, and an optional custom menu bar icon
are stored locally with macOS `UserDefaults`. Profiles and pending App Intent
commands use the Barline App Group container with atomic files, validation, and
a previous-valid backup. Profile archives are accessed only after an explicit
user import or export action.

For display-specific profiles, Barline derives an opaque SHA-256 alias from
public display hardware values so a uniquely identifiable monitor can be
recognized after reconnecting. Raw hardware values are not stored. Profile
exports include the opaque alias so reconnect behavior survives import; sharing
an archive therefore shares a stable pseudonymous monitor identifier.

Barline writes operational messages to Apple's unified logging system. Current
item-operation logs use internal tags rather than menu item titles. Support
bundle export is explicit, bounded, sanitized, and reviewed before saving.

## Permissions

- Accessibility is required for cross-application discovery and mutation;
  settings, profile metadata, search, and diagnostics remain available in
  degraded mode.
- Screen & System Audio Recording is optional and supports item-image previews
  and menu bar appearance features.

Barline explains and requests a permission only after the user invokes a
feature that needs it. Denial and revocation retain the degraded experience;
grants are rechecked when the app becomes active.

## Network access

Debug builds disable automatic updates. Release builds trust only Barline's
committed Sparkle public key and GitHub-hosted signed appcast. Apart from update
checks, explicit links, and dependency resolution during development, Barline
has no intentional network feature.

## Sharing and deletion

Barline does not automatically share local data. Preferences can be removed by
deleting Barline's macOS preferences after quitting the app. Profiles can be
exported, selectively imported, deleted, or reset; last-known-good recovery is
available from Profiles settings.

This document describes the development tree, not a published binary release.
