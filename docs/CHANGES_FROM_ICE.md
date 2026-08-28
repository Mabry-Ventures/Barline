# Material changes from Ice

This ledger records shipping differences between Barline and the imported Ice
baseline. It is updated with each milestone.

## Import and audit

- Preserved the exact Ice compatibility-fork history at
  `79654cd8c249e2a1465a262cfda7175346fe7772`.
- Added Barline provenance, licensing, execution, and baseline-audit records.
- No behavior changed during the import or measured baseline.

## Rebrand and build system

- Renamed the project, application, schemes, and XPC helper to Barline while
  preserving Git history.
- Centralized product identity, bundle identifiers, architecture, deployment
  target, signing placeholders, Swift mode, and update placeholders in
  `Config/*.xcconfig`.
- Replaced the Ice cube artwork with an original generated Barline icon and
  retained deterministic icon and acknowledgements generation sources under
  `script/`.
- Raised Barline-owned code to Swift 6 complete strict-concurrency checking and
  warnings-as-errors, repairing actor ownership and unsafe shared state exposed
  by the compiler.
- Added the canonical local build/launch/verification script and Codex Run
  environment action.
- Removed shipping upstream support, donation, signing, bundle, and update
  destinations. Historical Ice names remain only in provenance, attribution,
  baseline records, and legacy preference keys needed for migration.

## Remaining Barline product changes

The authoritative implementation ledger is `docs/EXECUTION_PLAN.md`. Product
identity, private-API isolation, profiles, Focus Filters, App Intents, per-
display layouts, deterministic and semantic local search, diagnostics,
recovery, tests, local delivery gates, and Barline-owned distribution will be
recorded here only after implementation and validation.
