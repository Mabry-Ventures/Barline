# Contributing to Barline

Participation in this project is governed by our
[Code of Conduct](CODE_OF_CONDUCT.md). Report conduct concerns privately to
dev@mabryventures.com.

Barline is GPLv3 software derived from Ice. Contributions retain their authorship
in Git history and must be compatible with the repository's GPLv3 distribution.
Read [NOTICE.md](NOTICE.md), [docs/UPSTREAM.md](docs/UPSTREAM.md), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before changing attribution,
dependencies, or assets.

## Set up

Use an Apple Silicon Mac running macOS 26 with Xcode 26.6. macOS 27 is a separate,
unqualified compatibility lane, not a substitute for the current toolchain.

```bash
git clone https://github.com/Mabry-Ventures/mv-barline.git
cd mv-barline
./script/bootstrap.sh
```

Follow [Building Barline](docs/BUILDING.md) for build and launch commands. The
development launch script stops running Barline processes and launches an
ad-hoc-signed build. Do not use it to replace an installed notarized candidate
with the same bundle identifier: that can invalidate permission identity and
installed qualification. Use the documented `full --installed` workflow instead.

`./script/bootstrap.sh --install-tools` installs the tools listed in `Brewfile`
without `sudo`. It does not change the machine-wide Xcode selection.

## Validate a change

Run the smallest relevant checks while working, then:

```bash
./script/ci.sh fast
```

Before a pull request or merge, run:

```bash
./script/ci.sh full
```

The full gate is intentionally fail-closed. Its fixture-regression, UI,
accessibility, XPC-interruption, support-bundle, and performance scripts must
all execute successfully. Runtime probes require the relevant macOS privacy
and Developer Tools grants. Arrange a bounded interactive session for tests
that use the pointer or open interfaces; do not run repeated focus-stealing
tests on an unattended desktop. Do not publish a local commit status until
every required step actually ran on the exact source candidate.

All macOS compilation, tests, signing, notarization, and release validation are
local. GitHub Actions is limited to Linux repository hygiene.

## Engineering boundaries

- Keep pure models and rules in `BarlineCore`.
- Keep private WindowServer symbols and capture implementations inside
  `BarlineMenuService` behind typed contracts.
- Treat snapshots as untrusted and retain the last-known-good state.
- Use Swift 6 strict concurrency and avoid blocking or filesystem work on the
  main actor.
- Do not add accounts, analytics, remote AI, advertising, subscriptions, or
  feature gates.
- Never commit signing credentials, notarization credentials, private Sparkle
  keys, provisioning profiles, or `Config/Local.xcconfig`.

## Pull requests

Keep changes focused and use the repository pull-request template. Include the
exact commit SHA, toolchain, local gate, test evidence, accessibility impact,
migration impact, and macOS 27 status. Do not describe an unavailable test or
credential-bound step as passing. File bugs and discuss changes in
[Issues](https://github.com/Mabry-Ventures/mv-barline/issues), then submit a focused
[pull request](https://github.com/Mabry-Ventures/mv-barline/pulls).

Preserve unrelated changes, upstream remotes, the recorded vendor baseline,
and license notices. Keep local logs, result bundles, generated output, and
credentials out of Git. Review attachments for private data before sharing.
