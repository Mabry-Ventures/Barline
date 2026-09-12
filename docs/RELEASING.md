# Releasing Barline

Barline binary releases are produced only by the local credentialed pipeline.
`script/release.sh --unsigned` is an explicit non-distributable topology
diagnostic. The default path validates
nested Developer ID signatures and App Group profiles, rejects
`get-task-allow`, notarizes, staples, runs Gatekeeper, signs the update, and
generates an appcast, checksums, SPDX SBOM, exact source archive, and a signed,
notarized drag-to-Applications disk image.

## Preconditions

A release candidate must be a clean `main` commit with passing fast, full, and
release gates for the same SHA. Version/build values must match across the app,
XPC service, and any extension. The exact source must receive a documented
annotated tag and remain available with GPLv3 license, provenance, changes,
build instructions, lockfiles, project files, and notices.

## Required local pipeline

The credentialed extension of the local release pipeline must sign, notarize,
and publish without GitHub Actions. It archives into local scratch storage,
uses Xcode's Developer ID export step to distribution-sign the complete nested
code graph after removing non-arm64 code from prebuilt dependencies such as
Sparkle. It must validate that every Mach-O file is arm64-only, nested signing
order (including Sparkle helpers and Barline's XPC service), Developer ID
Application
signing, Hardened Runtime, release entitlements, absence of `get-task-allow`,
`codesign --verify --deep --strict`, notarization, stapling, and `spctl`.

The appcast embeds release notes that Sparkle shows in its update dialog. The
pipeline extracts only the list items from the CHANGELOG section for the exact
version and build, and fails if that section is missing, names a different
build, or has no list items.

The Sparkle private key is stored in Keychain account
`mabry-ventures-barline`; only its public key is committed. The canonical feed
is the `appcast.xml` asset on the latest GitHub release.

## Download artifacts

`Barline-<version>.dmg` is the first-install download: a read-only image
holding the stapled app beside an `Applications` shortcut. It is built with the
system `hdiutil` rather than a third-party packaging tool, signed with the same
Developer ID certificate that signed the app, notarized, stapled, and assessed
with `spctl`. `script/test-dmg-layout.sh` verifies the layout in the fast gate.

`Barline-<version>.zip` remains the Sparkle update payload. `generate_appcast`
scans every archive in the distribution folder, so the pipeline builds the disk
image only after the appcast exists and fails if the appcast enclosure is
anything but the zip.

The publication commit for a release that ships a disk image must move the
README download link, `site/src/index.html`, and the site release gate
(`site/scripts/release-gate.mjs` and `site/tests/`) from the zip to that
version's `.dmg` together. The site gate binds the homepage to the published
release, so this switch cannot land before the disk image exists on GitHub.

## Credentials

Signing identities belong in Keychain, notarization uses a `notarytool` Keychain
profile, Sparkle private material stays in Keychain or secure local storage, and
GitHub publishing uses existing `gh` authentication. Never place credentials in
source, tracked configuration, environment files, shell history, artifacts, or
GitHub Actions secrets.

Set `BARLINE_APP_PROVISIONING_PROFILE_SPECIFIER` and
`BARLINE_INTENTS_PROVISIONING_PROFILE_SPECIFIER` in ignored
`Config/Local.xcconfig`. Signed archives use a temporary local scratch directory
so File Provider metadata from a synced workspace cannot invalidate code signing.

Use `--notary-profile NAME` or `BARLINE_NOTARY_PROFILE` to select an existing
notarytool Keychain profile; never pass a password. The release script passes an
explicit Keychain path so a same-named credential in another Keychain backend
cannot be selected. It defaults to the login Keychain and may be overridden with
`--notary-keychain PATH` or `BARLINE_NOTARY_KEYCHAIN`. When profiles or
credentials are absent, only `--unsigned` may pass and is not a release claim.
Clean install and update-from-previous remain separately recorded gates. The
first public release records an update from the immediately preceding signed
candidate because no previous public Barline version exists.
