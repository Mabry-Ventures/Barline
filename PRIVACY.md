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
are stored locally with macOS `UserDefaults`. `BarlineCore` provides an
actor-isolated profile file store with atomic writes and a local backup, but the
app does not yet choose a production storage location or invoke that store.

Barline writes operational messages to Apple's unified logging system. Current
item-operation logs use internal tags and window identifiers rather than menu
item titles. Diagnostic export is not implemented; users should review any log
material before sharing it.

## Permissions

- Accessibility is currently required for menu bar discovery and arrangement.
- Screen & System Audio Recording is optional and supports item-image previews
  and menu bar appearance features.

The current development build opens its Permissions window when required
Accessibility access is missing. Contextual, feature-level permission handling
is not yet complete. Revoking either permission is done in System Settings.

## Network access

Automatic updates are compiled with Sparkle but disabled. There is no Barline
feed URL or public update key in the current build. Apart from explicit links
opened by the user and dependency resolution during development, the current
application has no intentional network feature.

## Sharing and deletion

Barline does not automatically share local data. Preferences can be removed by
deleting Barline's macOS preferences after quitting the app. A supported reset
and selective support-bundle workflow has not yet been implemented; see
[Known limitations](docs/KNOWN_LIMITATIONS.md).

This document describes the development tree, not a published binary release.
