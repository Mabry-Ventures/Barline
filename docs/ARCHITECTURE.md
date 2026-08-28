# Barline architecture

Barline currently consists of the SwiftUI/AppKit application, a pure Swift
`BarlineCore` package, and the embedded `BarlineMenuService` XPC helper.

## Runtime responsibilities

- `Barline` owns presentation, input observation, settings, permissions,
  update UI, and the projection of validated domain state.
- `BarlineCore` owns stable item identity, typed snapshots, validation,
  backend contracts, transactional coordination, profiles, and deterministic
  search. It imports Foundation only.
- `BarlineMenuService` owns compatibility probes and WindowServer access. It
  selects Tahoe, Golden Gate, or safe fallback behavior through live probes.
- `Shared` contains the Codable XPC envelope and utilities needed by both
  processes. The old direct compatibility wrappers are excluded from the app
  target and remain helper-only during the stable-identity migration.

The app communicates with the helper through Codable request and response
values. Synchronous transport calls run on the connection queue, never on the
caller's actor. Cancellation invalidates a connection generation so late
responses cannot become authoritative.

## State flow

1. The helper resolves required symbols dynamically and runs a behavioral
   enumeration probe.
2. The app requests a typed `MenuBarSnapshot` through `XPCMenuBarBackend`.
3. `MenuBarStateCoordinator` validates display geometry, active-space state,
   timestamp, generation, item identities, required controls, and continuity.
4. Only a valid candidate becomes current and last-known-good state.
5. Mutations take an explicit FIFO coordinator turn, validate before and
   after the operation, and restore the prior snapshot after failure.
6. Recovery invalidates the helper connection, re-probes, restores when the
   backend supports it, and refreshes authoritative state.

Recurring 1–10 second refresh and image-capture timers have been removed.
Refreshes are driven by application, workspace, wake, active-space, display,
theme, permission, and mutation events. One-shot debounce and auto-rehide
timers remain bounded interaction mechanics, not idle polling.

## Transitional boundary

The compatibility migration is deliberately staged to keep the imported app
usable. A helper-only legacy request set currently carries ephemeral window
numbers for existing layout and image code while those consumers are being
converted to stable `MenuBarItemID` values. The architectural gate remains
open until those requests, app-side raw window fields, and app-side event
synthesis are removed. See `PRIVATE_API_BOUNDARY.md`.

