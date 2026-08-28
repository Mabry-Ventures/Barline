# Compatibility firewall status

`script/ci/architecture_firewall.sh` is the strict Milestone 3 boundary check.
It rejects direct `@_silgen_name` declarations, references to the enumerated
private WindowServer symbols outside `BarlineMenuService`, raw
`CGWindowID` use in Barline or BarlineCore, and obvious recurring timer/sleep
polling loops.

The check intentionally is not part of `ci.sh fast` during the active Milestone
3 migration. It is mandatory in `ci.sh full`; a violation is a real failure,
not an advisory skip. Event delays, bounded retries, and one-shot presentation
timers are not classified as frequent polling by this static check and still
require code review and runtime evidence.

## Current migration checkpoint

As of the Milestone 4 automation checkpoint on 2026-08-28, the strict check is
expected to fail: legacy compatibility wrappers still live under `Shared`, raw
`CGWindowID` values still appear in the app domain, and the input-quiescence
path contains a sleep loop. This is evidence that Milestone 3 is still in
progress. It must not be waived or described as a passing firewall until the
lead completes the boundary migration and reruns the check.
