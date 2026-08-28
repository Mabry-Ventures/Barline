# Profile schema

`BarlineCore` defines profile schema version **6** and archive format version
**1**. The models, validator, JSON codec, migrations, file store, Ice-import
preview, and Swift Testing coverage exist. The app uses the Barline App Group
container (with an Application Support fallback for unsigned local builds),
provides profile capture/apply/delete and Presentation-profile UI, and routes
activation through the validated transactional coordinator.

## Model

A `BarlineProfile` contains:

- UUID, name, optional SF Symbol name, creation/update dates, and schema version
- default visible, hidden, and always-hidden item order
- groups and spacers
- per-display layout/group/spacer overrides
- static and retained light/dark tint, exact gradient stops, border, and shadow
  variants, the dynamic-mode flag, exact shape/end-cap/inset details, and item
  spacing
- shelf behavior, reveal triggers, auto-rehide, overlap behavior, and hotkey

Item identity combines a normalized bundle identifier with at least one of an
Accessibility identifier, title, user alias, or fallback fingerprint. A bundle
identifier alone is rejected as insufficiently stable. Display identifiers are
normalized strings; the code does not yet persist the hardware metadata needed
for reconnect reconciliation.

## Validation

The validator rejects unsupported versions, blank names, reversed timestamps,
unstable or duplicate items, duplicate displays/groups/spacers, unknown group
members or spacer anchors, spacer widths outside 1...160 points, invalid
appearance values (including fractional item spacing and malformed colors),
unsupported shelf routing, negative auto-rehide delays, invalid hotkeys,
duplicate profiles, malformed archives, and empty archives.

JSON uses ISO-8601 dates, sorted keys, pretty printing, and no escaped slashes.
Archives contain `formatVersion`, `exportedAt`, and a nonempty `profiles` array.

## Migrations

- v1 to v2 converts three legacy item-order arrays into `layout` and adds
  groups, spacers, and display overrides.
- v2 to v3 adds appearance, shelf, reveal, auto-rehide, and overlap defaults.
- v3 to v4 adds the explicit smart, timed, or focused-app auto-rehide strategy;
  legacy workspace checkpoints decode a missing strategy as timed.
- v4 to v5 adds optional dynamic light/dark appearance variants.
- v5 to v6 adds exact gradient stops, border details, and shape details;
  legacy profiles and workspace checkpoints receive deterministic defaults for
  fields the older schemas did not model, and ambiguous solid-plus-gradient
  tints are canonicalized to the historically applied gradient.

Migration is forward-only. Unknown future schema/archive versions fail safely;
there is no downgrade writer. Import validates each migrated profile before it
is returned.

## File persistence

`ProfileFileStore` is an actor whose caller supplies an app-owned directory. It
uses `profiles.json` and `profiles.backup.json`, creates the directory with
owner-only permissions, validates before saving, writes atomically, retains the
previous valid primary as backup, recovers a missing/corrupt primary from a
valid backup, and fails closed when both files are unreadable. Tests use
temporary directories and the shipping app selects the shared App Group
`group.com.mabryventures.Barline`.

The Ice importer recognizes only `com.jordanbaird.Ice` and
`com.lxy1992.Ice`, creates a confirmation-required preview from an explicit
preference snapshot and current menu bar snapshot, discloses unsupported
appearance/hotkey data, and requires explicit replacement on repeated import.

## Activation precedence

The implemented resolver orders sources from lowest to highest precedence:
configured default, Focus, Shortcut, App Intent, manual, recovery. Ties use the
newest request and then a stable UUID ordering. `ProfileManager` retains one
request per source, resolves it before every activation, and commits an active
profile only after the coordinator validates the resulting snapshot; failures
restore the prior layout and profile authority.
