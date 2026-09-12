# Known limitations and release status

This page describes the boundaries of Barline 1.0.11. Release evidence is bound
to its exact source and signed binary; it is not blanket approval for later
changes.

## Compatibility

- The target platform is Apple Silicon running macOS 26. Intel is unsupported.
- macOS 27 has not been runtime-qualified. Compilation or results on macOS 26
  do not establish support for macOS 27.
- The secondary shelf and graphical layout editor require an always-visible
  menu bar. Auto-hide uses native reveal instead; see
  [supported configurations](SUPPORTED_CONFIGURATIONS.md).
- Cross-application arrangement relies on unsupported WindowServer behavior.
  macOS updates and third-party item behavior can affect it. Missing or ambiguous
  identities cannot safely authorize a layout mutation.
- Multiple displays, notch/overflow, physical reconnect, sleep/wake, full-screen
  Spaces, and actual permission changes require their own runtime evidence.
  Synthetic tests alone do not certify those configurations.

## Features in qualification

Saved layouts, import/export, transactional activation, recovery, native Focus
Filter integration, groups, and search favorites/aliases are included.

Display-layout authoring, explainable context rules, and per-item shortcuts are
included. Barline integrates through native Focus Filters and does not provide
an independent catalog of macOS Focus modes.

Automatic rules are optional and start paused after relaunch. Resume is explicit;
manual layout changes pause them again. Rules never restart other applications
to change system item spacing; such layouts must first be applied manually.

Deterministic search remains available without Apple Intelligence. Optional
on-device interpretation and Spotlight behavior have separate availability and
validation requirements; see [search architecture](SEARCH_AND_APPLE_INTELLIGENCE.md).

## Current reliability and distribution boundary

Barline 1.0.11 (build 36) was published on September 11, 2026. Before
publication it passed its source-bound local macOS 26.6.2 gate, which covers
shelf open and close timing, helper recovery, and fixture native-menu and
popover journeys on a local build; Developer ID signing; notarization; stapling;
Gatekeeper; and a signed Sparkle update from build 34 followed by a cold launch.
Installed click journeys against the signed app and the installed-candidate gate
were not run before publication and remain open. Historical failed attempts
remain in local evidence and are not overwritten by later passes. Clean
installation on a separate Mac, physical configuration, accessibility, and
release-duration soak remain distinct evidence classes.

Barline 1.0.12 (build 37) is the release candidate. Before publication it must
pass its exact-head local gate, Developer ID signing, notarization and stapling
of both the zip and the disk image, Gatekeeper, and a signed Sparkle update from
the installed 1.0.11 (build 36) followed by a cold launch. Clean installation,
including the move-to-Applications offer and the first-run walkthrough, is
qualified separately on a Mac that has never run Barline.

A click that closes the shelf within about 300 ms of opening it can be ignored
when Barline's WindowServer confirmation for that presentation times out. The
shelf stays open and the next click closes it. Automated rapid open/close
testing observed this in about 1 of 300 cycles; ordinary click timing is
expected to reach that window far less often. Its cause is still under
investigation, and it is accepted as a known limitation for 1.0.11.

The public support site and hosted Stripe checkout do not qualify the app and do
not unlock features.

See [release requirements](RELEASING.md), [the test matrix](TEST_MATRIX.md),
and the [reliability-first acceptance contract](RELIABILITY_FIRST.md).
