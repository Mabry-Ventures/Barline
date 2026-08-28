# Barline

**Your menu bar, in order.**

Barline is an Apple-native, privacy-first menu bar workspace manager for Apple
Silicon Macs. It can organize visible, hidden, and always-hidden status items;
reveal them on demand; present an overflow shelf; search items; and customize
menu bar appearance and spacing.

Barline is a GPLv3 successor derived from
[Ice](https://github.com/jordanbaird/Ice) and its
[macOS compatibility fork](https://github.com/lxy1992/Ice). See
[NOTICE.md](NOTICE.md), [docs/UPSTREAM.md](docs/UPSTREAM.md), and
[docs/CHANGES_FROM_ICE.md](docs/CHANGES_FROM_ICE.md) for full attribution and
source provenance.

> Barline is under active development and does not yet have a public binary
> release or signed update feed. Do not download binaries from an Ice release
> page expecting them to be Barline.

## Requirements

- macOS 26.0 or later
- Apple Silicon (`arm64`)
- Accessibility permission for cross-application menu bar arrangement
- Screen & System Audio Recording permission for item-image previews

Barline uses unsupported WindowServer behavior for cross-application status
item management. The compatibility layer is designed to fail safely, but macOS
updates can temporarily reduce that capability. Settings and recovery must
remain available in a degraded state.

## Privacy

Barline has no account, cloud service, analytics SDK, advertising, remote AI,
or menu bar inventory upload. Local development builds make no network request
other than resolving source dependencies. Release builds will use the network
only for Barline's signed update feed and explicit user-opened links.

## Current features

- Visible, hidden, and always-hidden sections
- Click, hover, scroll, swipe, and hotkey reveal controls
- Automatic rehide and application-menu overlap handling
- Drag-and-drop and keyboard-assisted layout editing
- Secondary shelf for overflow and notched displays
- Fast local item search
- Menu bar tint, gradient, border, shadow, and shape controls
- Item spacing, launch at login, and update infrastructure

Profiles, Focus Filters, App Intents, stable per-display layouts, Core Spotlight,
on-device natural-language interpretation, diagnostics, and transactional
recovery are being implemented in the tracked milestones. Documentation is
updated only when the corresponding code and tests exist.

## Build and run

Install Xcode 26.6, clone the repository with its submodule-free Git history,
then run:

```bash
./script/build_and_run.sh --verify
```

Useful variants:

```bash
./script/build_and_run.sh --clean --verify
./script/build_and_run.sh --release --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

The script uses an explicit Xcode path, a repository-local DerivedData folder,
an ad-hoc local signature, and the committed Swift package lock. It never
changes the machine-wide selected Xcode.

## Local validation

The current rebrand gate is:

```bash
swiftlint lint --strict --config .swiftlint.yml
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Barline.xcodeproj -scheme Barline \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

The canonical `script/ci.sh` command surface and full local evidence bundle are
introduced in Milestone 4. No GitHub-hosted macOS or self-hosted runner is used.

## Installation and releases

No installable Barline release is published yet. Release packages will include
the exact source tag and archive, GPLv3 license, notices, build instructions,
checksums, and signed update metadata. Signing and notarization remain local.

## Contributing and support

Repository, issue, donation, and security-contact URLs will be added when the
canonical public repository is established. Donations will never unlock or
gate functionality.

## License

Barline is licensed under the [GNU General Public License v3](LICENSE). Complete
corresponding source, project files, lockfiles, and build scripts must accompany
every distributed binary.
