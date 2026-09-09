import Testing
@testable import BarlineCore

struct MenuBarCapabilityProbeCacheTests {
    private let available = MenuBarCapabilities(
        canSnapshot: true, canMove: true, canReveal: true,
        canActivate: true, canRestore: true, canCapture: true
    )

    @Test func unavailableStartupRecoversOnLaterDemand() {
        var cache = MenuBarCapabilityProbeCache()
        var calls = 0
        #expect(cache.resolve(at: 0) { calls += 1; return .fallback } == .fallback)
        for tick in 1..<100 {
            #expect(cache.resolve(at: UInt64(tick)) { calls += 1; return available } == .fallback)
        }
        #expect(calls == 1)
        #expect(cache.resolve(at: 2_000_000_000) { calls += 1; return available } == available)
        #expect(calls == 2)
    }

    @Test func laterUnavailabilityIsNotPermanentlyMasked() {
        var cache = MenuBarCapabilityProbeCache()
        #expect(cache.resolve(at: 0) { available } == available)
        #expect(cache.resolve(at: 2_000_000_000) { .fallback } == .fallback)
        #expect(cache.resolve(at: 4_000_000_000) { available } == available)
    }

    @Test func clockRegressionFailsClosedWithoutProbing() {
        var cache = MenuBarCapabilityProbeCache()
        _ = cache.resolve(at: 10) { available }
        var calls = 0
        #expect(cache.resolve(at: 9) { calls += 1; return available } == .fallback)
        #expect(calls == 0)
    }

    @Test func uptimeNearMaximumDoesNotOverflowOrLoop() {
        var cache = MenuBarCapabilityProbeCache()
        var calls = 0
        _ = cache.resolve(at: UInt64.max - 1) { calls += 1; return .fallback }
        #expect(cache.resolve(at: UInt64.max) { calls += 1; return available } == .fallback)
        #expect(calls == 1)
    }
}
