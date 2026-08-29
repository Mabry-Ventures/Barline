# Releasing Barline

Barline has no published binary release. `script/release.sh --unsigned` is an
explicit non-distributable topology diagnostic. The default path validates
nested Developer ID signatures and App Group profiles, rejects
`get-task-allow`, notarizes, staples, runs Gatekeeper, signs the update, and
generates an appcast, checksums, SPDX SBOM, and exact source archive.

## Preconditions

A release candidate must be a clean `main` commit with passing fast, full, and
release gates for the same SHA. Version/build values must match across the app,
XPC service, and any extension. The exact source must receive a documented
annotated tag and remain available with GPLv3 license, provenance, changes,
build instructions, lockfiles, project files, and notices.

## Required local pipeline

The credentialed extension of the local release pipeline must sign, notarize,
and publish
without GitHub Actions. It must validate arm64-only output, nested signing order
(including Sparkle helpers and Barline's XPC service), Developer ID Application
signing, Hardened Runtime, release entitlements, absence of `get-task-allow`,
`codesign --verify --deep --strict`, notarization, stapling, and `spctl`.

The Sparkle private key is stored in Keychain account
`mabry-ventures-barline`; only its public key is committed. The canonical feed
is the `appcast.xml` asset on the latest GitHub release.

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
notarytool Keychain profile; never pass a password. When profiles or credentials
are absent, only `--unsigned` may pass and is not a release claim. Clean install
and update-from-previous remain separately recorded manual gates.
