@testable import BarlineCore
import Testing

struct MenuBarPresentationPolicyTests {
    @Test func pickerCannotReopenDuringActivationOrRestoration() {
        for activating in [false, true] {
            for restoring in [false, true] {
                #expect(MenuBarPresentationPolicy.allowsPresentation(
                    activating: activating, restoring: restoring
                ) == (!activating && !restoring))
            }
        }
    }

    @Test func temporaryRevealHasOnlyOnePresentationUntilRestorationSucceeds() {
        let first = MenuBarItemID(bundleIdentifier: "fixture", title: "first")
        let second = MenuBarItemID(bundleIdentifier: "fixture", title: "second")
        let layout = [first, second]
        var pending: Set<MenuBarItemID> = [first]
        #expect(MenuBarPresentationPolicy.shelfItemIDs(layout, temporarilyRevealed: pending) == [second])
        // Retrying or deferring restoration keeps the item out of the shelf;
        // it does not rewrite the saved layout or discard the obligation.
        #expect(MenuBarPresentationPolicy.shelfItemIDs(layout, temporarilyRevealed: pending) == [second])
        pending.remove(first)
        #expect(MenuBarPresentationPolicy.shelfItemIDs(layout, temporarilyRevealed: pending) == layout)
    }

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
