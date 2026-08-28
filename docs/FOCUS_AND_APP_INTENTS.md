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

These types do not register anything with Shortcuts, Siri, Spotlight, or Focus.

## Required integration contract

The implementation uses Apple's official Focus Filter/App Intents APIs, passes
only stable profile identifiers and one-time command tokens across the App
Group boundary, loads
the profile from a shared App Group store, validate it again in the app, and
apply it transactionally. Activation and deactivation must preserve the prior
profile, respect source precedence, serialize rapid changes, and roll back on a
failed layout mutation.

An ordinary profile-switch App Intent remains available when Focus Filter
invocation is unavailable. The extension may not call private WindowServer APIs
or become a second source of truth.

## Evidence and remaining boundary

- Extension target, matching host/extension entitlements, App Group identifier,
  embedded topology, and generated metadata compile locally.
- Core tests cover activation precedence, rapid serialized changes, validation,
  and rollback.
- Real Shortcuts and Focus invocation still requires a correctly provisioned,
  signed application. No matching local development certificate is available,
  so system registration and invocation are not claimed.
