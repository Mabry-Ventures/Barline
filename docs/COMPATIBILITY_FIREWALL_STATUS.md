# Compatibility firewall status

`script/ci/architecture_firewall.sh` is the strict Milestone 3 boundary check.
It rejects direct `@_silgen_name` declarations, references to the enumerated
private WindowServer symbols outside `BarlineMenuService`, raw
`CGWindowID` use in Barline or BarlineCore, and obvious recurring timer/sleep
polling loops.

The check is mandatory in `ci.sh full`; a violation is a real failure, not an
advisory skip. Event delays, bounded retries, and one-shot presentation timers
are not classified as frequent polling by this static check and still require
code review and runtime evidence.

## Current migration checkpoint

As of the Milestone 3 completion checkpoint on 2026-08-28, the strict check
passes. Additional searches confirm that `WindowInfo`, `.windowID`, the legacy
request/response family, and `sendLegacy` are absent from the app, Core, and
shared XPC envelope. The app binary contains no unresolved CGS/SLS symbols;
private symbol names remain only in the helper for dynamic resolution. The
signed helper kill/relaunch probe also passes.
