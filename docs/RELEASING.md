# Releasing Barline

Barline is not distribution-ready and has no published binary release.
`script/release.sh` now performs the clean-SHA unsigned archive dry run,
validates app/XPC/App-Intents topology, arm64 output, plists, App Group source
entitlements, and required GPL/privacy/security documents, then records the
credential-bound steps it did not perform. Sparkle has no Barline appcast, feed
URL, public key, or private EdDSA material.

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

It must also generate a Sparkle EdDSA signature and appcast, SHA-256 checksum,
SBOM, source archive, release notes, and GPL source links, then record clean
installation and update-from-previous-version results.

## Credentials

Signing identities belong in Keychain, notarization uses a `notarytool` Keychain
profile, Sparkle private material stays in Keychain or secure local storage, and
GitHub publishing uses existing `gh` authentication. Never place credentials in
source, tracked configuration, environment files, shell history, artifacts, or
GitHub Actions secrets.

When credentials are absent, only unsigned archive topology and a dry run may
be reported. Current baseline evidence proves an unsigned arm64 archive can be
created; it does not prove signing, Gatekeeper acceptance, notarization, update,
installation, or publication.
