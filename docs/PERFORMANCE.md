# Performance and energy

Barline has no release-qualified performance baseline yet.

The imported baseline was observed only at the permission gate: approximately
43.6 MB physical footprint and 44.3 MB peak during a short run. That is not an
idle, ordinary-use, energy, or soak measurement and must not be used as a
marketing claim.

`script/test-performance-smoke.sh` builds and verifies the app, then compiles
and runs `script/measure-barline-shelf-responsiveness.swift` against the shelf.
The probe uses an argument-gated Debug-only distributed notification to invoke
the same section toggle after the visible status item is present; Release has
no test bridge. The latest available-host run completed 20/20 presentations
with no timeout and a 27.6 ms p95, inside the 250 ms feedback budget.
`script/test-soak.sh` repeats the state/profile/search suites and then exercises
helper interruption plus the responsiveness probe. Its latest integration run
completed all 10 cycles. Candidate-bound results are still required after the
implementation SHA is committed and clean.

The default `./script/ci.sh soak` remains a short development smoke. Release
preparation uses `./script/ci.sh soak --release`, which defaults to a bounded
1,800-second run against an actual Release build. It sends a standard production
Apple `reopen` event and measures the synchronous application response rather
than invoking the Debug-only runtime bridge. It repeatedly executes
snapshot/state/profile/search tests in SwiftPM's Release configuration,
requires XPC helper replacement while preserving the app PID, and samples
app/helper RSS and CPU plus Barline cache size. A changed app PID invalidates
the run, so RSS growth remains continuous and enforced. The production reopen
probe does not claim shelf responsiveness: real shelf interaction remains a
separate Accessibility-bound release gate. It writes
`resources.csv` and `summary.json`
under `.artifacts/soak/<sha>/`, including the exact SHA, dirty state, host,
toolchain, cycle counts, resource extrema/growth, configured guards, and whether
the full 30-minute duration actually completed. A reduced duration is useful
only to validate the harness when explicitly enabled with
`BARLINE_SOAK_HARNESS_VALIDATION=1`; its verdict is `HARNESS_PASS`, never
candidate evidence.

## Required measurements

Release evidence must measure launch responsiveness, idle CPU/wakeups, physical
memory, snapshot/refresh latency, profile activation, deterministic search,
shelf presentation, XPC restart, and cache size on representative Apple Silicon
hardware. A 30-minute soak must repeat snapshot/profile/search/shelf and XPC
restart cycles while sampling memory and checking for unbounded cache growth.

Record raw commands, samples, percentiles, timeouts, hardware, display topology,
macOS/Xcode versions, commit SHA, and artifacts. Establish budgets from measured
representative data before enforcing or publishing numerical claims.
