# Focus Filters and App Intents

## Current status

Barline contains an embedded App Intents extension with an `AppEntity` profile
query, Open Barline, Presentation Mode, Switch Profile, App Shortcuts, and a
`SetFocusFilterIntent`. Xcode 26.6 compiles the target and extracts its metadata.

`BarlineCore` supplies the supporting domain concepts:

- activation sources for Focus, Shortcuts, App Intents, manual changes, default
  selection, and recovery
- deterministic activation-source precedence
- typed command operations that can request profile activation or replacement
- profile validation and import/export codecs

## Integration contract

The implementation uses Apple's official Focus Filter/App Intents APIs, passes
only stable profile identifiers through an atomic one-file-per-command App Group
inbox. A Darwin notification is a low-latency rescan hint; the durable inbox is
authoritative across app termination. The app validates the requested profile
again and applies it transactionally. Activation and deactivation preserve the prior
profile, respect source precedence, serialize rapid changes, and roll back on a
failed layout mutation.

An ordinary profile-switch App Intent remains available when Focus Filter
invocation is unavailable. The extension may not call private WindowServer APIs
or become a second source of truth.

## Evidence and remaining boundary

- Extension target, matching host/extension entitlements, App Group identifier,
  embedded topology, and generated metadata compile locally.
- Core tests cover inbox ordering/idempotence, activation precedence, rapid
  serialized changes, validation, and rollback.
- Real Shortcuts and Focus invocation still requires a correctly provisioned,
  signed application with App Group provisioning. System registration and
  invocation are not claimed until that candidate evidence exists.
