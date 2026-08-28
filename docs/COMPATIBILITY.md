# Compatibility strategy

Barline supports macOS 26 on Apple Silicon. Compatibility is selected by live
capability probes; the operating-system version only determines which backend
gets the first opportunity to probe.

- `TahoeMenuBarBackend` is the macOS 26 implementation.
- `GoldenGateMenuBarBackend` is the macOS 27 implementation point. It is
  compile-guarded and probe-selected, but cannot be runtime-certified without
  a macOS 27 host.
- `FallbackMenuBarBackend` exposes no unsupported mutation capability. The app
  must keep settings, profiles, search metadata, diagnostics, import/export,
  System Settings handoff, and reset/recovery accessible in this state.

A capability is unavailable when a symbol is missing, a behavioral probe
fails, or an operation produces a typed compatibility error. A transient empty
or implausibly collapsed snapshot never replaces last-known-good state.

The production lane is Xcode 26.6 / Swift 6.3 on macOS 26. The local machine
has that lane. Xcode 27 and a macOS 27 runtime are not installed, so macOS 27
results must remain informational and unverified.

