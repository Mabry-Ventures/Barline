# Known limitations and release status

This page describes the development tree, not a published release certificate.
No public binary download is currently available. The next candidate remains
blocked until its required tests pass on the final source and signed binary.

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

Saved layouts, import/export, transactional activation, recovery, and native
Focus Filter integration are implemented. Groups and search favorites/aliases
have implementation and automated coverage, but their installed interaction,
keyboard, accessibility, and persistence checks remain release requirements.

Display-layout authoring, explainable context rules, and per-item shortcuts now
have implementation and local regression checks. They are not qualified release features. Native
Focus activation/deactivation and manual-override behavior need real system
execution; Barline does not provide an independent catalog of macOS Focus modes.

Automatic rules are optional and start paused after relaunch. Resume is explicit;
manual layout changes pause them again. Rules never restart other applications
to change system item spacing; such layouts must first be applied manually.

Deterministic search remains available without Apple Intelligence. Optional
on-device interpretation and Spotlight behavior have separate availability and
validation requirements; see [search architecture](SEARCH_AND_APPLE_INTELLIGENCE.md).

## Current reliability and distribution boundary

A shelf interaction timed out during installed qualification. Later successful
diagnostic runs do not, by themselves, explain or resolve the original failure.
The final candidate must demonstrate reliable open, close, target activation,
and restoration behavior before publication.

Signed/notarized candidates and local upgrade tests have been produced. Those
results are source- and binary-specific, not blanket approval for new changes.
Builds, automated regressions, installed journeys, physical scenarios,
accessibility checks, and release-duration soak are distinct evidence classes.
Any unavailable or deferred lane must be stated explicitly in release scope.

The public support site and checkout have staging work, but staged website QA
does not qualify the app or establish production-domain availability.

See [release requirements](RELEASING.md), [the test matrix](TEST_MATRIX.md),
and the [reliability-first acceptance contract](RELIABILITY_FIRST.md).
