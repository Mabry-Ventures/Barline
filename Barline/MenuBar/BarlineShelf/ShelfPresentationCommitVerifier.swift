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

/// Reconciles public AppKit state with a typed helper-side WindowServer probe.
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

            let decision = await ShelfPresentationCommitPolicy.evaluate(
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
    ) async -> ShelfPresentationObservation {
        let windowServer = await (try? BarlineMenuService.Connection.shared
            .shelfPresentationObservation(
                ownerProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
                targetDisplayID: targetScreen.displayID
            )) ?? .unavailable

        return ShelfPresentationObservation(
            appKitIsVisible: panel.isVisible,
            appKitIsOnActiveSpace: panel.isOnActiveSpace,
            appKitFrame: ShelfPresentationRect(panel.frame),
            targetScreenFrame: ShelfPresentationRect(targetScreen.frame),
            windowServerIsPresentOnscreen: windowServer.roleIsPresentOnscreen,
            windowServerOwnerMatches: windowServer.ownerMatches,
            windowServerIntersectsTargetDisplay: windowServer.intersectsTargetDisplay
        )
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
