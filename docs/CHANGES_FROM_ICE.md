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
  `script/`. Generic dot, ellipsis, and warning resources plus the rearranging
  documentation media remain unchanged Ice-derived GPL material and are
  recorded in `docs/DEPENDENCIES.md`.
- Raised Barline-owned code to Swift 6 complete strict-concurrency checking and
  warnings-as-errors, repairing actor ownership and unsafe shared state exposed
  by the compiler.
- Added the canonical local build/launch/verification script and Codex Run
  environment action.
- Removed shipping upstream support, donation, signing, bundle, and update
  destinations. Historical Ice names remain only in provenance, attribution,
  baseline records, and legacy preference keys needed for migration.

## Product platform and delivery

- Isolated WindowServer/private-symbol work in the embedded XPC helper behind
  typed stable-ID contracts, validation, recovery, and an architecture firewall.
- Added versioned profiles with atomic App Group persistence, backup recovery,
  transactional activation, precedence, Presentation templates, and settings UI.
- Added an App Intents/Focus extension whose bridge carries stable identifiers
  and tokens only; menu-bar mutations remain app/helper-owned.
- Replaced inherited fuzzy-only search with deterministic Core ranking for menu
  items/profiles plus privacy-bounded Core Spotlight synchronization.
- Added opt-in, review-before-save bounded diagnostics.
- Added a real fixture application, unit/integration/UI targets, test plan,
  local gate orchestration, soak harness, and unsigned release dry run.

The exact remaining system, hardware, macOS 27, and credential boundaries are
tracked in `docs/EXECUTION_PLAN.md` and `docs/KNOWN_LIMITATIONS.md`.
