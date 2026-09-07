@testable import BarlineCore
import Testing

@Suite("Deferred presentation dismissal ownership")
struct PresentationEpochTests {
    @Test("An unchanged presentation permits its deferred dismissal")
    func currentPresentation() {
        var epoch = PresentationEpoch()
        epoch.advance()
        let request = epoch.lease
        #expect(epoch.owns(request))
    }

    @Test("A close invalidates an outstanding dismissal")
    func closedPresentation() {
        var epoch = PresentationEpoch()
        epoch.advance()
        let request = epoch.lease
        epoch.advance()
        #expect(!epoch.owns(request))
    }

    @Test("A deferred result for A cannot dismiss reopened B")
    func reopenedPresentation() {
        var epoch = PresentationEpoch()
        epoch.advance() // Open A; asynchronous rehide begins.
        let requestA = epoch.lease
        epoch.advance() // Close A while the helper lookup is suspended.
        epoch.advance() // Open B before the old lookup finishes.
        let requestB = epoch.lease
        #expect(!epoch.owns(requestA))
        #expect(epoch.owns(requestB))
    }

    @Test("Repeated lifetime changes never revive a stale request")
    func repeatedPresentations() {
        var epoch = PresentationEpoch()
        let oldRequest = epoch.lease
        for _ in 0 ..< 100 {
            epoch.advance()
            #expect(!epoch.owns(oldRequest))
        }
    }
}
