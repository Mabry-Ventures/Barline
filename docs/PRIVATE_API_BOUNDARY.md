# Private API boundary

Barline cannot enumerate and manipulate other applications' status items with
public macOS APIs alone. Unsupported behavior is therefore treated as a
contained compatibility exception, not a general application dependency.

## Enforced now

- There are no `@_silgen_name` declarations.
- Private entry points are resolved through guarded `dlopen` and `dlsym`.
- Missing symbols return unavailable capabilities or typed errors rather than
  preventing app launch.
- The app target excludes the helper's direct compatibility implementation.
- The app has no unresolved CGS or SkyLight linker symbols.
- Tahoe, Golden Gate, and fallback backend types are present behind
  `MenuBarBackend`.
- Typed capability, snapshot, health, restart, and error values cross XPC.
- WindowServer enumeration for the typed snapshot runs in the helper.
- `MenuBarItemID` is the only item identity outside the helper.
- Image/background capture, point queries, event synthesis, and ephemeral
  interface observation execute in the helper through semantic requests.
- The legacy raw-window request family and app compatibility facade are gone.
- Helper cancellation schedules a bounded reconnect and the signed
  interruption test observes a replacement process.

## Completed migration gate

Milestone 3 evidence establishes all of the following:

1. `MenuBarItemID` is the sole item identity outside the helper.
2. The helper resolves a stable ID to a newly validated ephemeral window
   reference immediately before an operation.
3. Event synthesis and window-specific image capture run only in the helper.
4. The legacy raw-window XPC cases and app compatibility facade are deleted.
5. Static source and binary firewall checks pass; the app binary has no
   unresolved CGS/SLS symbols or SkyLight linkage.
6. The signed helper interruption and recovery test passes.

Dynamic resolution does not make the behavior public API or Mac App Store
safe. Barline remains a direct-distribution application and must report failed
probes honestly through compatibility diagnostics.
