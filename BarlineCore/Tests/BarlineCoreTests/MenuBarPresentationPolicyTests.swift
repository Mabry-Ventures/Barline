@testable import BarlineCore
import Testing

struct MenuBarPresentationPolicyTests {
    @Test func autoHideAlwaysFallsBackWithoutChangingRequestedPreference() {
        for requestedShelf in [false, true] {
            #expect(!MenuBarPresentationPolicy.usesShelf(
                requestedShelf: requestedShelf, systemAutoHideEnabled: true
            ))
            #expect(MenuBarPresentationPolicy.usesShelf(
                requestedShelf: requestedShelf, systemAutoHideEnabled: false
            ) == requestedShelf)
        }
    }
}
