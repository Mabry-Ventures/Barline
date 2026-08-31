import Foundation

/// A platform-neutral rectangle used by the pure presentation policy.
public struct ShelfPresentationRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func hasPositiveAreaIntersection(with other: Self) -> Bool {
        let intersectionWidth = min(x + width, other.x + other.width) - max(x, other.x)
        let intersectionHeight = min(y + height, other.y + other.height) - max(y, other.y)
        return intersectionWidth > 0 && intersectionHeight > 0
    }
}

/// A privacy-safe observation of an app-owned panel's presentation state.
public struct ShelfPresentationObservation: Equatable, Sendable {
    public let appKitIsVisible: Bool
    public let appKitIsOnActiveSpace: Bool
    public let appKitFrame: ShelfPresentationRect
    public let targetScreenFrame: ShelfPresentationRect
    public let windowServerIsPresentOnscreen: Bool
    public let windowServerOwnerMatches: Bool
    public let windowServerIntersectsTargetDisplay: Bool

    public init(
        appKitIsVisible: Bool,
        appKitIsOnActiveSpace: Bool,
        appKitFrame: ShelfPresentationRect,
        targetScreenFrame: ShelfPresentationRect,
        windowServerIsPresentOnscreen: Bool,
        windowServerOwnerMatches: Bool,
        windowServerIntersectsTargetDisplay: Bool
    ) {
        self.appKitIsVisible = appKitIsVisible
        self.appKitIsOnActiveSpace = appKitIsOnActiveSpace
        self.appKitFrame = appKitFrame
        self.targetScreenFrame = targetScreenFrame
        self.windowServerIsPresentOnscreen = windowServerIsPresentOnscreen
        self.windowServerOwnerMatches = windowServerOwnerMatches
        self.windowServerIntersectsTargetDisplay = windowServerIntersectsTargetDisplay
    }
}

/// The first failed invariant when evaluating a shelf presentation.
public enum ShelfPresentationCommitFailure: Equatable, Sendable {
    case notVisible
    case inactiveSpace
    case emptyFrame
    case outsideTargetScreen
    case missingWindowServerWindow
    case ownerMismatch
    case outsideTargetDisplay
}

/// The result of evaluating a shelf presentation observation.
public enum ShelfPresentationCommitDecision: Equatable, Sendable {
    case committed
    case pending(ShelfPresentationCommitFailure)
}

/// Decides whether AppKit and WindowServer agree that the shelf is onscreen.
public enum ShelfPresentationCommitPolicy {
    public static func evaluate(
        _ observation: ShelfPresentationObservation
    ) -> ShelfPresentationCommitDecision {
        guard observation.appKitIsVisible else {
            return .pending(.notVisible)
        }
        guard observation.appKitIsOnActiveSpace else {
            return .pending(.inactiveSpace)
        }
        guard observation.appKitFrame.width > 0, observation.appKitFrame.height > 0 else {
            return .pending(.emptyFrame)
        }
        guard observation.appKitFrame.hasPositiveAreaIntersection(
            with: observation.targetScreenFrame
        ) else {
            return .pending(.outsideTargetScreen)
        }
        guard observation.windowServerIsPresentOnscreen else {
            return .pending(.missingWindowServerWindow)
        }
        guard observation.windowServerOwnerMatches else {
            return .pending(.ownerMismatch)
        }
        guard observation.windowServerIntersectsTargetDisplay else {
            return .pending(.outsideTargetDisplay)
        }
        return .committed
    }
}

/// Requires a stable presentation across consecutive display-frame samples.
public struct ShelfPresentationCommitTracker: Sendable {
    private let requiredConsecutiveSamples: Int
    private var consecutiveCommittedSamples = 0

    public init(requiredConsecutiveSamples: Int = 2) {
        self.requiredConsecutiveSamples = max(1, requiredConsecutiveSamples)
    }

    public mutating func observe(_ decision: ShelfPresentationCommitDecision) -> Bool {
        switch decision {
        case .committed:
            consecutiveCommittedSamples += 1
        case .pending:
            consecutiveCommittedSamples = 0
        }
        return consecutiveCommittedSamples >= requiredConsecutiveSamples
    }
}
