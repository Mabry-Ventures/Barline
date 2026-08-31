# Focus Filters and App Intents

## Current status

Barline contains an embedded App Intents extension with an `AppEntity` profile
query, Open Barline, Switch Profile, App Shortcuts, and a native
`SetFocusFilterIntent`. The Focus Filter lets the user select any saved Barline
menu bar layout directly in System Settings > Focus; Barline does not create a
separate kind of Focus or a special Presentation mode.

Apple's public API does not expose the user's Focus-mode names or identifiers to
third-party apps. `FocusFilterSuggestionContext` contains no public mode
metadata, and `SetFocusFilterIntent.current` returns only Barline's configured
filter parameters. Barline therefore cannot mirror Work, Personal, or custom
Focus modes in its own settings. The Layouts & Focus pane links to System
Settings, where Apple requires each Focus-to-layout assignment to be made.

`BarlineCore` supplies the supporting domain concepts:

- activation sources for Focus, Shortcuts, App Intents, manual changes, default
  selection, and recovery
- deterministic activation-source precedence
- typed command operations that can request profile activation or replacement
- profile validation and import/export codecs

## Integration contract

The implementation uses Apple's official Focus Filter/App Intents APIs and
passes only the selected stable profile identifier through an atomic
one-file-per-command App Group inbox. A `nil` selection from the system ends the
Focus-owned activation. A Darwin notification is a low-latency rescan hint; the
durable inbox is authoritative across app termination. The app validates the
requested profile again and applies it transactionally. Activation and
deactivation preserve the prior workspace, respect source precedence, serialize
rapid changes, and roll back on a failed layout mutation.

An ordinary profile-switch App Intent remains available when Focus Filter
invocation is unavailable. The extension may not call private WindowServer APIs
or become a second source of truth.

## Evidence and remaining boundary

- Extension target, matching host/extension entitlements, App Group identifier,
  embedded topology, and generated metadata compile locally.
- Core tests cover Focus-profile inbox ordering/idempotence, activation precedence, rapid
  serialized changes, validation, and rollback.
- Real Shortcuts and Focus invocation still requires a correctly provisioned,
  signed application with App Group provisioning. System registration and
  invocation are not claimed until that candidate evidence exists.
