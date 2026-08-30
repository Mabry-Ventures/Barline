# Local CI

Barline app correctness is validated locally on Apple Silicon. GitHub Actions
runs repository hygiene only; it never builds, signs, notarizes, tests, or
publishes the macOS app.

## Setup

Run `./script/bootstrap.sh` to verify the host, Xcode, packages, and tools. Use
`--install-tools` to install the pinned tool set declared in `Brewfile`, and
`--install-hooks` to opt into the repository-local pre-commit and pre-push
hooks. Bootstrap never uses `sudo` or changes the global Xcode selection.

## Gates

- `./script/ci.sh fast` resolves dependencies, checks changed Swift formatting,
  runs strict SwiftLint, builds/tests BarlineCore with coverage, validates the
  Xcode project, and runs the same repository hygiene used on Linux.
- `./script/ci.sh nonfocus` adds the architecture firewall, unsigned
  Debug/Release builds, analysis, explicit test-plan build plus unit/integration
  execution, regression fixtures, XCUITest against `BarlineFixture`,
  accessibility, and support-bundle privacy without activating production
  Barline.
- `./script/ci.sh full` adds production XPC interruption, UI smoke, performance,
  and reopen-burst gates. These gates can present or activate production
  Barline and require an interactive validation session where focus changes are
  acceptable.
- `./script/ci.sh release` runs full and then the clean-candidate unsigned
  archive/topology release dry run. Credentialed signing and publication remain
  separate external gates.
- `./script/ci.sh xcode27 --xcode /Applications/Xcode-27.app` requires an
  explicit Xcode 27. It reports runtime support as unverified unless the host is
  actually running macOS 27.
- `./script/ci.sh soak` repeats state/profile/search tests (10 cycles by
  default), then runs helper interruption and responsiveness probes. Override
  the bounded count with `BARLINE_SOAK_ITERATIONS`.

Every run writes logs, result bundles where available, command records, and a
machine-readable `summary.json` under ignored `.artifacts/ci/<sha>/`.

The UI smoke gate launches the exact local build and verifies Barline's visible
Control Center status item without clicking permission controls. XCUITest uses `BarlineFixture`; it fails
with a clear administrator boundary when Developer Tools automation mode is
disabled. The accessibility gate uses the macOS AX tree without requesting
access; it returns unavailable when the invoking host cannot expose the fixture
window through `AXWindows`.
The XPC gate forcibly interrupts the embedded helper and requires automatic
replacement while the app survives. The support-bundle privacy gate audits both
the product exporter and source/logging boundary.

## Commit status publishing

`./script/ci.sh full --publish-status` and the corresponding `xcode27` mode
require a clean worktree and existing GitHub CLI authentication. Full publishes
`local/macos-arm64` through the commit status API for the captured SHA, verifies
HEAD is unchanged, and cannot publish success if any required gate was missing
or failed. The non-focus lane cannot publish this protected success context.
Xcode 27 uses the optional `local/macos27-beta` context until final runtime
validation supports renaming it.

Hook bypass is possible with Git's documented `--no-verify` flag for an
emergency, but the reason and replacement evidence must be recorded in the PR.
