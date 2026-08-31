@testable import BarlineCore
import Testing

struct ShelfPresentationCommitPolicyTests {
    private let targetFrame = ShelfPresentationRect(x: 0, y: 0, width: 1440, height: 900)
    private let shelfFrame = ShelfPresentationRect(x: 900, y: 840, width: 400, height: 40)

    @Test
    func commitsWhenAppKitAndWindowServerAgree() {
        #expect(ShelfPresentationCommitPolicy.evaluate(observation()) == .committed)
    }

    @Test
    func preservesValidAppKitPresentationWhenWindowServerObserverIsUnavailable() {
        let candidate = observation(windowServerIsPresentOnscreen: false)

        #expect(ShelfPresentationCommitPolicy.evaluateAppKit(candidate) == .committed)
        #expect(
            ShelfPresentationCommitPolicy.evaluate(candidate) ==
                .pending(.missingWindowServerWindow)
        )
    }

    @Test(arguments: [
        ShelfPresentationCommitDecision.pending(.notVisible),
        .pending(.inactiveSpace),
        .pending(.emptyFrame),
        .pending(.outsideTargetScreen),
    ])
    func rejectsInvalidLocalPresentation(expected: ShelfPresentationCommitDecision) {
        let candidate: ShelfPresentationObservation = switch expected {
        case .committed:
            observation()
        case .pending(.notVisible):
            observation(appKitIsVisible: false)
        case .pending(.inactiveSpace):
            observation(appKitIsOnActiveSpace: false)
        case .pending(.emptyFrame):
            observation(appKitFrame: ShelfPresentationRect(x: 0, y: 0, width: 0, height: 0))
        case .pending(.outsideTargetScreen):
            observation(appKitFrame: ShelfPresentationRect(x: 2000, y: 2000, width: 100, height: 40))
        case .pending:
            observation()
        }

        #expect(ShelfPresentationCommitPolicy.evaluateAppKit(candidate) == expected)
    }

    @Test(arguments: [
        ShelfPresentationCommitDecision.pending(.notVisible),
        .pending(.inactiveSpace),
        .pending(.emptyFrame),
        .pending(.outsideTargetScreen),
        .pending(.missingWindowServerWindow),
        .pending(.ownerMismatch),
        .pending(.outsideTargetDisplay),
    ])
    func rejectsEachUncommittedState(expected: ShelfPresentationCommitDecision) {
        let candidate: ShelfPresentationObservation = switch expected {
        case .committed:
            observation()
        case .pending(.notVisible):
            observation(appKitIsVisible: false)
        case .pending(.inactiveSpace):
            observation(appKitIsOnActiveSpace: false)
        case .pending(.emptyFrame):
            observation(appKitFrame: ShelfPresentationRect(x: 0, y: 0, width: 0, height: 0))
        case .pending(.outsideTargetScreen):
            observation(appKitFrame: ShelfPresentationRect(x: 2000, y: 2000, width: 100, height: 40))
        case .pending(.missingWindowServerWindow):
            observation(windowServerIsPresentOnscreen: false)
        case .pending(.ownerMismatch):
            observation(windowServerOwnerMatches: false)
        case .pending(.outsideTargetDisplay):
            observation(windowServerIntersectsTargetDisplay: false)
        }

        #expect(ShelfPresentationCommitPolicy.evaluate(candidate) == expected)
    }

    @Test
    func acceptsPartiallyClippedShelfWithVisibleArea() {
        let frame = ShelfPresentationRect(x: -100, y: 840, width: 300, height: 40)
        #expect(
            ShelfPresentationCommitPolicy.evaluate(observation(appKitFrame: frame)) == .committed
        )
    }

    @Test
    func rejectsShelfThatOnlyTouchesScreenEdge() {
        let frame = ShelfPresentationRect(x: 1440, y: 840, width: 300, height: 40)
        #expect(
            ShelfPresentationCommitPolicy.evaluate(observation(appKitFrame: frame)) ==
                .pending(.outsideTargetScreen)
        )
    }

    @Test
    func requiresTwoConsecutiveCommittedSamples() {
        var tracker = ShelfPresentationCommitTracker()

        let firstCommit = tracker.observe(.committed)
        let interrupted = tracker.observe(.pending(.missingWindowServerWindow))
        let secondCommit = tracker.observe(.committed)
        let stableCommit = tracker.observe(.committed)

        #expect(!firstCommit)
        #expect(!interrupted)
        #expect(!secondCommit)
        #expect(stableCommit)
    }

    private func observation(
        appKitIsVisible: Bool = true,
        appKitIsOnActiveSpace: Bool = true,
        appKitFrame: ShelfPresentationRect? = nil,
        windowServerIsPresentOnscreen: Bool = true,
        windowServerOwnerMatches: Bool = true,
        windowServerIntersectsTargetDisplay: Bool = true
    ) -> ShelfPresentationObservation {
        ShelfPresentationObservation(
            appKitIsVisible: appKitIsVisible,
            appKitIsOnActiveSpace: appKitIsOnActiveSpace,
            appKitFrame: appKitFrame ?? shelfFrame,
            targetScreenFrame: targetFrame,
            windowServerIsPresentOnscreen: windowServerIsPresentOnscreen,
            windowServerOwnerMatches: windowServerOwnerMatches,
            windowServerIntersectsTargetDisplay: windowServerIntersectsTargetDisplay
        )
    }
}
