# Barline

**Your menu bar, organized. Your Mac, uninterrupted.**

Barline is a free, open-source menu bar utility for Apple Silicon Macs. Keep
everyday items visible, tuck the rest away, and reveal them when you need them.
No account, subscription, advertising, or paid feature tier.

## Download status

An installable public release is **not available yet**. The next candidate is
under development and qualification; a successful build is not a release pass.
Qualified downloads will appear in this repository's
[Releases](https://github.com/Mabry-Ventures/Barline/releases), together with
corresponding source, checksums, license notices, and release notes.

Do not download an Ice binary expecting it to be Barline. Do not disable macOS
security protections to install an unofficial build.

## What Barline does

- Organizes visible, hidden, and always-hidden menu bar sections.
- Reveals hidden items through its menu bar control, shelf, or keyboard controls.
- Saves menu bar layouts and integrates with Apple's Focus Filters.
- Searches menu bar items locally and customizes their appearance and spacing.
- Provides reviewed diagnostic export and layout recovery tools.

The development tree also contains new group, search-personalization, display,
rule, and shortcut work. Implementation and testing are in progress; these are
not a promise of qualified release features. See
[known limitations](docs/KNOWN_LIMITATIONS.md) for the current boundaries.

## Compatibility and permissions

The current target is **macOS 26 on Apple Silicon (`arm64`)**. Intel Macs are
not supported. macOS 27 has not been runtime-qualified; a newer OS version is
not automatically a supported configuration.

The secondary shelf and graphical layout editor require an always-visible
system menu bar. Automatically hidden menu bars use a native reveal fallback.
Read [supported configurations](docs/SUPPORTED_CONFIGURATIONS.md) before testing
full-screen, notched, or multiple-display setups.

Accessibility permission enables cross-application discovery and arrangement.
Screen & System Audio Recording permission enables optional item-image previews
and appearance features. Settings, saved layout metadata, search, diagnostics,
and recovery remain available without granting every permission.

Barline relies on unsupported WindowServer behavior. macOS updates can affect
it. Our reliability goal is to preserve your last good state, keep your Mac
usable, and make recovery clear—not to promise that failures are impossible.

## Privacy and optional support

Menu bar data stays local. Barline has no analytics, inventory upload, or remote
AI service. Release builds use a signed update feed; external links open only
when you choose them. Read the [privacy policy](PRIVACY.md).

Barline is donationware. Optional contributions never unlock features, and
the app does not display payment reminders.

## Help and contributions

Start with [troubleshooting](FREQUENT_ISSUES.md). Report reproducible bugs or
suggest improvements through
[GitHub Issues](https://github.com/Mabry-Ventures/Barline/issues). Review any
diagnostic attachment and redact private information before sharing it.
Security concerns belong under the [security policy](SECURITY.md), not in a
public bug report.

Developers: see [Contributing](CONTRIBUTING.md), [Building](docs/BUILDING.md),
and the [architecture guide](docs/ARCHITECTURE.md). Iteration uses
`./script/ci.sh fast`; complete local qualification uses `./script/ci.sh full`.
All macOS builds, testing, signing, and notarization run locally. GitHub Actions
runs Linux repository hygiene only.

## License and origins

Barline is GPLv3 software derived from
[Jordan Baird's Ice](https://github.com/jordanbaird/Ice) and
[Xinyan Lu's macOS compatibility fork](https://github.com/lxy1992/Ice).
It is an independent project, not an endorsement by its upstream authors.

See [LICENSE](LICENSE), [NOTICE.md](NOTICE.md),
[third-party notices](THIRD_PARTY_NOTICES.md),
[provenance](docs/PROVENANCE.md), and [changes from Ice](docs/CHANGES_FROM_ICE.md).
Complete corresponding source and required notices accompany distributed builds.
