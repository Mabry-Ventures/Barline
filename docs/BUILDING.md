# Building Barline from source

Barline is built from this repository without generated project files or Git
submodules. The committed Xcode project, shared schemes, test plan, Swift
package lockfiles, scripts, license, and notices are the complete corresponding
source for a release.

## Requirements

- An Apple Silicon Mac running macOS 26 or later
- Xcode 26.6 with its command-line tools installed
- Homebrew only when installing the development lint tools from `Brewfile`

Xcode 27 is an additional compatibility lane when that toolchain and runtime
are available; it is not a substitute for the production Xcode 26.6 lane.

## Bootstrap

Clone the repository, select its directory, and verify the environment:

```bash
git clone https://github.com/Mabry-Ventures/mv-barline.git
cd mv-barline
./script/bootstrap.sh
```

To install the pinned lint tools and configure the repository-local Git hooks:

```bash
./script/bootstrap.sh --install-tools --install-hooks
```

The bootstrap script resolves the dependencies pinned by
`Barline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
and `BarlineCore/Package.resolved`. It does not change the system-wide Xcode
selection. Machine-specific signing values belong in ignored
`Config/Local.xcconfig`; begin with `Config/Local.example.xcconfig`.
For Developer ID releases, set the app and Intents provisioning-profile
specifier variables to profiles bound to the configured team and App Group.

## Build and run

Build an unsigned arm64 Debug application, apply an ad-hoc local signature, and
verify that it launches:

```bash
./script/build_and_run.sh --clean --verify
```

The canonical direct build is:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Barline.xcodeproj -scheme Barline \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Accessibility permission is required only when exercising cross-application
menu bar discovery and mutation. Settings, diagnostics, search metadata, and
profile management remain available without it.

## Test

Run the quick source and domain gate during development:

```bash
./script/ci.sh fast
```

Run the complete production-toolchain gate on the Mac that will publish its
candidate status:

```bash
./script/ci.sh full
```

For an already-installed notarized candidate, do not replace it with an ad-hoc
same-identifier build. Set `BARLINE_CANDIDATE_APP`, `BARLINE_SOURCE_SHA` and a
dedicated `BARLINE_INSTALLED_EVIDENCE_DIR`, then run `./script/ci.sh full --installed`.
The directory must contain four source/binary-bound target-interface receipts
(`native-left`, `native-right`, `popover-left`, `popover-reuse`). The installed
journey writes them only after the real target action, restoration and pointer
checks pass, using `BARLINE_EVIDENCE_OUTPUT` and `BARLINE_JOURNEY_LANE`.
The full gate adds 20-sample performance and forced-helper-recovery receipts.
Use a fresh directory per qualification attempt: receipts are never overwritten;
retain failed logs separately. Missing, failed, duplicate, wrong-source or
wrong-binary receipts fail qualification. Synthetic writer/validator tests are
not runtime evidence. Build products live outside the synchronized workspace;
logs, result bundles and summaries remain under ignored `.artifacts/` paths.

The full gate includes Debug and Release builds, static analysis, test-plan
execution, fixture regressions, XPC interruption, UI and Accessibility probes,
privacy checks, and responsiveness measurements. XCUITest needs Developer Tools
automation authorization, and the Accessibility runtime probe needs the same
permission granted to the invoking Codex or terminal host.

For a major release, run the resource-sampled 30-minute soak against a clean,
committed candidate:

```bash
./script/ci.sh soak --release
```

If Xcode 27 and a macOS 27 runtime are installed, run the optional compatibility
lane with the explicit Xcode path documented by `./script/ci.sh --help`.

## Distribution diagnostics and release

Validate archive topology without producing a distributable binary:

```bash
./script/release.sh --unsigned
```

The unsigned result is diagnostic only. A public release must use the default
credentialed path with the Mabry Ventures Developer ID identity, App Group
provisioning profiles, a `notarytool` Keychain profile, and the Sparkle Ed25519
private key stored outside the repository. See [RELEASING.md](RELEASING.md) for
the signed, notarized, stapled, Gatekeeper-assessed release procedure.

## License and provenance

Barline is GPLv3 software derived from Ice. Preserve `LICENSE`, `NOTICE.md`,
`THIRD_PARTY_NOTICES.md`, dependency lockfiles, and the provenance documents
when redistributing source or binaries. See [PROVENANCE.md](PROVENANCE.md),
[UPSTREAM.md](UPSTREAM.md), and [CHANGES_FROM_ICE.md](CHANGES_FROM_ICE.md).
