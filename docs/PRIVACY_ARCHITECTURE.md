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
- The host app remains unsandboxed because it manages other applications' menu
  bar items; Release uses Hardened Runtime. The host and sandboxed App Intents
  extension share only the Barline application-group entitlement.

The compatibility migration is complete. Typed capability, snapshot,
mutation, capture, environment, health, recovery, and last-known-good
contracts cross XPC; private symbols and raw window identifiers remain
helper-only. See [compatibility firewall status](COMPATIBILITY_FIREWALL_STATUS.md).

## Storage

Current app settings and optional custom icon data use `UserDefaults`. Runtime
window metadata and captured images are held in memory. Profiles use the shared
App Group container with atomic primary/backup persistence. Search synchronizes
only the closed `SearchDocument` fields to Barline's private Spotlight domain.
Support bundles are bounded JSON, require an in-app review confirmation and a
user-selected destination, and omit backend messages and raw environment
identifiers.

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

Complete permission-revocation behavior, runtime log-redaction observation,
and local no-network verification remain required before distribution.
