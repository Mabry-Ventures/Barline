/// Demand-driven capability observations. No timer, task, or retry loop is owned
/// here. Callers serialize access and supply a monotonic uptime clock.
public struct MenuBarCapabilityProbeCache: Sendable {
    private var lastProbe: UInt64?
    private var cached = MenuBarCapabilities.fallback
    public static let intervalNanoseconds: UInt64 = 2_000_000_000

    public init() {}

    public mutating func resolve(
        at uptime: UInt64,
        probe: () -> MenuBarCapabilities
    ) -> MenuBarCapabilities {
        if let lastProbe {
            // A regressed clock must not expose stale positive capability or
            // create an uncontrolled stream of new probes.
            guard uptime >= lastProbe else { return .fallback }
            if uptime - lastProbe < Self.intervalNanoseconds { return cached }
        }
        lastProbe = uptime
        cached = probe()
        return cached
    }
}
