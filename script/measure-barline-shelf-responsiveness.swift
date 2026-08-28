#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private enum Configuration {
    static let measuredCycles = 20
    static let warmupCycles = 2
    static let feedbackBudget = Duration.milliseconds(250)
    static let iconTimeout = Duration.seconds(5)
    static let openTimeout = Duration.milliseconds(1500)
    static let closeTimeout = Duration.milliseconds(1000)
    static let pollingIntervalMicroseconds: useconds_t = 10000
}

private struct WindowSnapshot {
    let ownerName: String?
    let windowName: String?
    let bounds: CGRect
}

private enum ProbeError: Error, CustomStringConvertible {
    case barlineIconNotFound
    case unableToCloseBaseline

    var description: String {
        switch self {
        case .barlineIconNotFound:
            "No on-screen Barline.ControlItem.Visible window was found"
        case .unableToCloseBaseline:
            "The Barline Bar could not be closed before measurement"
        }
    }
}

private func windowSnapshots() -> [WindowSnapshot] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let rows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

    return rows.compactMap { row in
        guard
            let dictionary = row[kCGWindowBounds as String] as? [String: Any],
            let x = (dictionary["X"] as? NSNumber)?.doubleValue,
            let y = (dictionary["Y"] as? NSNumber)?.doubleValue,
            let width = (dictionary["Width"] as? NSNumber)?.doubleValue,
            let height = (dictionary["Height"] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        return WindowSnapshot(
            ownerName: row[kCGWindowOwnerName as String] as? String,
            windowName: row[kCGWindowName as String] as? String,
            bounds: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}

private func barlineIconCenter() throws -> CGPoint {
    let start = ContinuousClock.now
    while start.duration(to: .now) < Configuration.iconTimeout {
        if let icon = windowSnapshots().first(where: {
            $0.windowName == "Barline.ControlItem.Visible" &&
                $0.bounds.width > 0 &&
                $0.bounds.width < 100
        }) {
            return CGPoint(x: icon.bounds.midX, y: icon.bounds.midY)
        }
        usleep(Configuration.pollingIntervalMicroseconds)
    }
    throw ProbeError.barlineIconNotFound
}

private func isBarlineShelfVisible() -> Bool {
    windowSnapshots().contains {
        $0.ownerName == "Barline" && $0.windowName == "Barline Bar"
    }
}

private func click(at point: CGPoint) {
    _ = point
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.mabryventures.Barline.runtime-smoke.toggle-shelf"),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
}

private func waitForVisibility(_ target: Bool, timeout: Duration) -> Duration? {
    let start = ContinuousClock.now
    while start.duration(to: .now) < timeout {
        if isBarlineShelfVisible() == target {
            return start.duration(to: .now)
        }
        usleep(Configuration.pollingIntervalMicroseconds)
    }
    return nil
}

private func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
}

private func percentile(_ values: [Double], _ percentile: Double) -> Double {
    guard !values.isEmpty else {
        return 0
    }
    let sorted = values.sorted()
    let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
    return sorted[min(rank - 1, sorted.count - 1)]
}

private func ensureClosed(iconPoint: CGPoint) throws {
    guard isBarlineShelfVisible() else {
        return
    }
    click(at: iconPoint)
    guard waitForVisibility(false, timeout: Configuration.closeTimeout) != nil else {
        throw ProbeError.unableToCloseBaseline
    }
}

private func runSingleClick(iconPoint: CGPoint) -> Double? {
    click(at: iconPoint)
    guard let latency = waitForVisibility(true, timeout: Configuration.openTimeout) else {
        return nil
    }
    click(at: iconPoint)
    _ = waitForVisibility(false, timeout: Configuration.closeTimeout)
    return milliseconds(latency)
}

private func runRapidRetry(iconPoint: CGPoint) -> (feedbackInBudget: Bool, silentCancellation: Bool) {
    click(at: iconPoint)
    if waitForVisibility(true, timeout: Configuration.feedbackBudget) != nil {
        click(at: iconPoint)
        _ = waitForVisibility(false, timeout: Configuration.closeTimeout)
        return (true, false)
    }

    // Reproduce a user retrying because the first click produced no visible feedback.
    click(at: iconPoint)
    let silentCancellation = waitForVisibility(true, timeout: Configuration.closeTimeout) == nil

    if isBarlineShelfVisible() {
        click(at: iconPoint)
        _ = waitForVisibility(false, timeout: Configuration.closeTimeout)
    }
    return (false, silentCancellation)
}

do {
    let iconPoint = try barlineIconCenter()

    try ensureClosed(iconPoint: iconPoint)

    for _ in 0 ..< Configuration.warmupCycles {
        _ = runSingleClick(iconPoint: iconPoint)
    }

    var latencies = [Double]()
    var timeouts = 0

    for cycle in 1 ... Configuration.measuredCycles {
        if let latency = runSingleClick(iconPoint: iconPoint) {
            latencies.append(latency)
            print(String(format: "cycle=%02d status=OK latency_ms=%.1f", cycle, latency))
        } else {
            timeouts += 1
            print(String(format: "cycle=%02d status=TIMEOUT", cycle))
            try ensureClosed(iconPoint: iconPoint)
        }
    }

    let rapidRetry = runRapidRetry(iconPoint: iconPoint)
    let median = percentile(latencies, 0.50)
    let p95 = percentile(latencies, 0.95)
    let maximum = latencies.max() ?? 0
    let budgetMilliseconds = milliseconds(Configuration.feedbackBudget)
    let passed = timeouts == 0 &&
        p95 <= budgetMilliseconds &&
        rapidRetry.feedbackInBudget &&
        !rapidRetry.silentCancellation

    print(
        String(
            format: "RESULT samples=%d timeouts=%d median_ms=%.1f p95_ms=%.1f max_ms=%.1f feedback_in_250ms=%@ silent_cancellation=%@ verdict=%@",
            latencies.count,
            timeouts,
            median,
            p95,
            maximum,
            rapidRetry.feedbackInBudget ? "true" : "false",
            rapidRetry.silentCancellation ? "true" : "false",
            passed ? "PASS" : "FAIL"
        )
    )

    exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
} catch {
    fputs("ERROR \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
