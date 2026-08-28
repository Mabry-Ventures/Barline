# ADR 0002: Structured concurrency exceptions

- Status: Accepted
- Date: 2026-08-28

## Decision

Use structured tasks for application operations. Two contained exceptions are
permitted at the compatibility transport boundary:

- The XPC listener bridges Apple's synchronous reply callback to an async
  backend with one detached task and a semaphore. It runs inside the helper,
  owns no UI state, and always returns one bounded reply.
- XPC `sendSync` executes on the dedicated connection queue. Callers await a
  checked continuation and do not block the main actor.

Both exceptions use Sendable Codable values and connection generations so a
late reply from an invalidated helper cannot be accepted.

## Consequences

WindowServer work and synchronous XPC transport stay off the main actor while
the product state engine remains async. Transport tests must cover cancellation,
interruption, replacement-session creation, and stale reply rejection.

