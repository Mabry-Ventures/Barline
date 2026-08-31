//
//  ShelfPresentationCommitVerifier.swift
//  Barline
//

import AppKit
import BarlineCore

/// A bounded result from reconciling AppKit state with WindowServer state.
enum ShelfPresentationCommitResult: Equatable, Sendable {
    case committed
    case timedOut(lastFailure: ShelfPresentationCommitFailure)
    case cancelled
}

/// Verifies that an app-owned shelf window has committed to the active Space.
@MainActor
protocol ShelfPresentationCommitVerifying: AnyObject {
    func waitForCommit(
        panel: NSPanel,
        targetScreen: NSScreen
    ) async -> ShelfPresentationCommitResult
}

/// Uses public AppKit and Core Graphics state to verify shelf presentation.
@MainActor
final class ShelfWindowCommitVerifier: ShelfPresentationCommitVerifying {
    private let timeout: Duration
    private let sampleInterval: Duration
    private let requiredConsecutiveSamples: Int

    init(
        timeout: Duration = .milliseconds(300),
        sampleInterval: Duration = .milliseconds(16),
        requiredConsecutiveSamples: Int = 2
    ) {
        self.timeout = timeout
        self.sampleInterval = sampleInterval
        self.requiredConsecutiveSamples = requiredConsecutiveSamples
    }

    func waitForCommit(
        panel: NSPanel,
        targetScreen: NSScreen
    ) async -> ShelfPresentationCommitResult {
        let start = ContinuousClock.now
        var commitTracker = ShelfPresentationCommitTracker(
            requiredConsecutiveSamples: requiredConsecutiveSamples
        )
        var lastFailure = ShelfPresentationCommitFailure.notVisible

        while start.duration(to: .now) < timeout {
            guard !Task.isCancelled else {
                return .cancelled
            }

            let decision = ShelfPresentationCommitPolicy.evaluate(
                observation(panel: panel, targetScreen: targetScreen)
            )
            if commitTracker.observe(decision) {
                return .committed
            }
            switch decision {
            case .committed:
                break
            case let .pending(failure):
                lastFailure = failure
            }

            do {
                try await Task.sleep(for: sampleInterval)
            } catch {
                return .cancelled
            }
        }

        return .timedOut(lastFailure: lastFailure)
    }

    private func observation(
        panel: NSPanel,
        targetScreen: NSScreen
    ) -> ShelfPresentationObservation {
        let windowNumber = panel.windowNumber
        let rows = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            CGWindowID(windowNumber)
        ) as? [[String: Any]] ?? []
        let row = rows.first {
            ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == windowNumber
        }
        let ownerProcessIdentifier = (row?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        let isOnscreen = (row?[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        let windowServerFrame = row?[kCGWindowBounds as String]
            .flatMap(windowServerRect(from:))
        let targetDisplayFrame = ShelfPresentationRect(CGDisplayBounds(targetScreen.displayID))

        return ShelfPresentationObservation(
            appKitIsVisible: panel.isVisible,
            appKitIsOnActiveSpace: panel.isOnActiveSpace,
            appKitFrame: ShelfPresentationRect(panel.frame),
            targetScreenFrame: ShelfPresentationRect(targetScreen.frame),
            windowServerIsPresentOnscreen: row != nil && isOnscreen,
            windowServerOwnerMatches: ownerProcessIdentifier == ProcessInfo.processInfo.processIdentifier,
            windowServerIntersectsTargetDisplay: windowServerFrame?.hasPositiveAreaIntersection(
                with: targetDisplayFrame
            ) == true
        )
    }

    private func windowServerRect(from value: Any) -> ShelfPresentationRect? {
        guard
            let dictionary = value as? [String: Any],
            let x = (dictionary["X"] as? NSNumber)?.doubleValue,
            let y = (dictionary["Y"] as? NSNumber)?.doubleValue,
            let width = (dictionary["Width"] as? NSNumber)?.doubleValue,
            let height = (dictionary["Height"] as? NSNumber)?.doubleValue
        else {
            return nil
        }
        return ShelfPresentationRect(x: x, y: y, width: width, height: height)
    }
}

private extension ShelfPresentationRect {
    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }
}
