# Focus Filters and App Intents

## Current status

Barline does **not** currently contain an App Intents extension, a Focus Filter,
an `AppEntity`, or a shipping `SwitchBarlineProfileIntent`. No Focus or App
Intent behavior has been validated.

`BarlineCore` contains only the supporting domain concepts:

- activation sources for Focus, Shortcuts, App Intents, manual changes, default
  selection, and recovery
- deterministic activation-source precedence
- typed command operations that can request profile activation or replacement
- profile validation and import/export codecs

These types do not register anything with Shortcuts, Siri, Spotlight, or Focus.

## Required integration contract

The future implementation must use Apple's official Focus Filter/App Intents
APIs, pass only stable profile identifiers across extension boundaries, load
the profile from a shared App Group store, validate it again in the app, and
apply it transactionally. Activation and deactivation must preserve the prior
profile, respect source precedence, serialize rapid changes, and roll back on a
failed layout mutation.

An ordinary profile-switch App Intent must remain available when Focus Filter
invocation is unavailable. The extension may not call private WindowServer APIs
or become a second source of truth.

## Evidence still required

- extension target, entitlements, App Group container, and generated metadata
- Focus activation/deactivation and rapid-switch tests
- App Intent entity lookup and profile-switch tests
- manual-override and rollback behavior
- real Shortcuts/Focus execution on supported macOS

