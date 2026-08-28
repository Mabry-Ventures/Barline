# ADR 0001: Compatibility service boundary

- Status: Accepted, migration in progress
- Date: 2026-08-28

## Decision

Keep pure state and product contracts in `BarlineCore`; put unsupported
WindowServer symbol resolution, ephemeral window references, behavioral
probes, event synthesis, and window-specific capture in the embedded
`BarlineMenuService`; expose stable Codable domain values to the app.

The app uses one `MenuBarStateCoordinator` actor as the authority for current
and last-known-good snapshots. A separate FIFO gate is required because Swift
actors can reenter while awaiting backend operations.

## Consequences

The helper can fail or restart without taking down presentation. Missing or
changed private symbols degrade capability instead of crashing launch. Every
mutation can be validated and rolled back around a stable identity.

The migration requires replacing the imported raw-window model and moving its
event synthesis and capture code. Temporary legacy XPC cases are explicitly
tracked as a failing architecture gate and are not an accepted final state.

