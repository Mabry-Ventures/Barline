# Contributing to Barline

Barline is GPLv3 software derived from Ice. Contributions retain their authorship
in Git history and must be compatible with the repository's GPLv3 distribution.
Read [NOTICE.md](NOTICE.md), [docs/UPSTREAM.md](docs/UPSTREAM.md), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before changing attribution,
dependencies, or assets.

## Set up

Use an Apple Silicon Mac running macOS 26 or later with Xcode 26.6:

```bash
./script/bootstrap.sh
./script/build_and_run.sh --verify
```

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
all execute successfully. The current support-bundle check fails because the
feature is absent, and runtime probes can remain unavailable without required
macOS privacy grants. Do not publish a local commit status until every required
step actually ran.

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
credential-bound step as passing. The canonical public repository and support
URLs are not configured yet, so this document intentionally contains no issue
or pull-request URL.
