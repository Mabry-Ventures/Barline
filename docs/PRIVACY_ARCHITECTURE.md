# Privacy architecture

Barline's privacy boundary is local-machine processing. There is no account,
cloud backend, analytics pipeline, advertising integration, or remote model.
The user-facing policy is [PRIVACY.md](../PRIVACY.md).

## Process and permission boundaries

- The main app owns UI and authoritative user settings.
- `BarlineMenuService` is an embedded XPC service intended to isolate private
  WindowServer access and window capture behind typed contracts.
- Accessibility is required for cross-application status-item discovery and
  arrangement.
- Screen Recording is optional and enables local item-image and appearance
  capture.
- App Sandbox is disabled; Release uses Hardened Runtime. Entitlement files are
  currently empty.

The compatibility migration is complete. Typed capability, snapshot,
mutation, capture, environment, health, recovery, and last-known-good
contracts cross XPC; private symbols and raw window identifiers remain
helper-only. See [compatibility firewall status](COMPATIBILITY_FIREWALL_STATUS.md).

## Storage

Current app settings and optional custom icon data use `UserDefaults`. Runtime
window metadata and captured images are held in memory. `BarlineCore` includes
an atomic profile file store, but the app has not assigned or invoked a shipping
location. A privacy-bounded Core Spotlight adapter exists but is not wired to
live app data. Support bundles are bounded JSON, require preview before write,
and omit backend messages and raw environment identifiers.

## Logging

Barline uses Apple unified logging under its bundle subsystem. Code review must
reject logs containing secrets, screen images, usernames, full paths, raw
process inventories, signing identities, or private profile names. Current
menu-item operation messages use stable semantic tags. The support-bundle
privacy gate passes synthetic secret, username, and path probes.

## Network boundary

Sparkle is linked but disabled and has no Barline feed or public key. The
current source contains no application `URLSession` or Network-framework client.
User-opened links and developer dependency resolution are outside automatic app
data transfer.

## Outstanding privacy gates

Contextual permissions, revocation behavior, runtime log-redaction tests, and
local no-network verification remain required before distribution.
