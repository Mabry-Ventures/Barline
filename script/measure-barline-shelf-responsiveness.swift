#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Darwin
import Foundation

private enum Configuration {
    static let measuredCycles = positiveEnvironmentInteger("BARLINE_PERFORMANCE_CYCLES") ?? 20
    static let warmupCycles = positiveEnvironmentInteger("BARLINE_PERFORMANCE_WARMUPS") ?? 2
    static let feedbackBudget = Duration.milliseconds(250)
    static let iconTimeout = Duration.seconds(5)
    static let openTimeout = Duration.milliseconds(1500)
    static let closeTimeout = Duration.milliseconds(1000)
    static let pollingIntervalMicroseconds: useconds_t = 10000
    static let probe = ProcessInfo.processInfo.environment["BARLINE_PERFORMANCE_PROBE"] ?? "runtime-smoke"
    static let enforceBudget = ProcessInfo.processInfo.environment["BARLINE_PERFORMANCE_ENFORCE_BUDGET"] != "0"

    private static func positiveEnvironmentInteger(_ name: String) -> Int? {
        guard
            let value = ProcessInfo.processInfo.environment[name],
            let integer = Int(value),
            integer > 0,
            integer <= 1000
        else {
            return nil
        }
        return integer
    }
}

private struct WindowSnapshot {
    let ownerName: String?
    let windowName: String?
    let bounds: CGRect
}

private func processIsRunning(_ processIdentifier: pid_t) -> Bool {
    kill(processIdentifier, 0) == 0
}

private enum ProbeError: Error, CustomStringConvertible {
    case applicationNotRunning
    case applicationProcessChanged
    case appleEventRejected(String)
    case recoveryFailed(String)
    case recoveryTimedOut
    case barlineIconNotFound
    case unableToCloseBaseline

    var description: String {
        switch self {
        case .applicationNotRunning:
            "The production Barline application is not running"
        case .applicationProcessChanged:
            "Barline changed processes during the reopen response probe"
        case let .appleEventRejected(message):
            "The production reopen request was rejected: \(message)"
        case let .recoveryFailed(reason):
            "The production reopen recovery reported failure: \(reason)"
        case .recoveryTimedOut:
            "The app-owned production reopen and Settings confirmation did not complete"
        case .barlineIconNotFound:
            "No on-screen Barline.ControlItem.Visible window was found"
        case .unableToCloseBaseline:
            "The Barline Bar could not be closed before measurement"
        }
    }
}

private func requestProductionReopen(
    processIdentifier: pid_t,
    timeout: Duration = Configuration.iconTimeout
) throws -> Double {
    let bundleIdentifier = "com.mabryventures.Barline"
    let recoveryGenerationKey = "ReopenRecoveryGeneration" as CFString
    let recoveryFailureKey = "ReopenRecoveryFailure" as CFString
    let recoverySucceededKey = "ReopenRecoverySucceeded" as CFString
    let applicationID = bundleIdentifier as CFString
    CFPreferencesAppSynchronize(applicationID)
    let startingGeneration = (CFPreferencesCopyAppValue(recoveryGenerationKey, applicationID) as? NSNumber)?.intValue ?? 0
    guard processIsRunning(processIdentifier) else {
        throw ProbeError.applicationNotRunning
    }
    let target = NSAppleEventDescriptor(processIdentifier: processIdentifier)
    let event = NSAppleEventDescriptor(
        eventClass: AEEventClass(kCoreEventClass),
        eventID: AEEventID(kAEReopenApplication),
        targetDescriptor: target,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    let start = ContinuousClock.now
    do {
        _ = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 5)
    } catch {
        throw ProbeError.appleEventRejected(error.localizedDescription)
    }
    guard
        processIsRunning(processIdentifier)
    else {
        throw ProbeError.applicationProcessChanged
    }
    while start.duration(to: .now) < timeout {
        CFPreferencesAppSynchronize(applicationID)
        let generation = (CFPreferencesCopyAppValue(recoveryGenerationKey, applicationID) as? NSNumber)?.intValue ?? 0
        if generation > startingGeneration {
            let succeeded = (CFPreferencesCopyAppValue(recoverySucceededKey, applicationID) as? NSNumber)?.boolValue ?? false
            guard succeeded else {
                let reason = CFPreferencesCopyAppValue(recoveryFailureKey, applicationID) as? String
                throw ProbeError.recoveryFailed(reason ?? "unknown compatibility error")
            }
            return milliseconds(start.duration(to: .now))
        }
        usleep(Configuration.pollingIntervalMicroseconds)
    }
    throw ProbeError.recoveryTimedOut
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

private func click(at _: CGPoint) throws {
    switch Configuration.probe {
    case "runtime-smoke":
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.mabryventures.Barline.runtime-smoke.toggle-shelf"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    default:
        fputs("error: shelf click is available only with the runtime-smoke probe\n", stderr)
        exit(2)
    }
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
    try click(at: iconPoint)
    guard waitForVisibility(false, timeout: Configuration.closeTimeout) != nil else {
        throw ProbeError.unableToCloseBaseline
    }
}

private func runSingleClick(iconPoint: CGPoint) throws -> Double? {
    try click(at: iconPoint)
    guard let latency = waitForVisibility(true, timeout: Configuration.openTimeout) else {
        return nil
    }
    try click(at: iconPoint)
    _ = waitForVisibility(false, timeout: Configuration.closeTimeout)
    return milliseconds(latency)
}

private func runRapidRetry(iconPoint: CGPoint) throws -> (feedbackInBudget: Bool, silentCancellation: Bool) {
    try click(at: iconPoint)
    if waitForVisibility(true, timeout: Configuration.feedbackBudget) != nil {
        try click(at: iconPoint)
        _ = waitForVisibility(false, timeout: Configuration.closeTimeout)
        return (true, false)
    }

    // Reproduce a user retrying because the first click produced no visible feedback.
    try click(at: iconPoint)
    let silentCancellation = waitForVisibility(true, timeout: Configuration.closeTimeout) == nil

    if isBarlineShelfVisible() {
        try click(at: iconPoint)
        _ = waitForVisibility(false, timeout: Configuration.closeTimeout)
    }
    return (false, silentCancellation)
}

do {
    if Configuration.probe == "apple-event-reopen" {
        guard
            let rawProcessIdentifier = ProcessInfo.processInfo.environment["BARLINE_EXPECTED_PID"],
            let processIdentifier = pid_t(rawProcessIdentifier),
            processIdentifier > 0,
            processIsRunning(processIdentifier)
        else {
            throw ProbeError.applicationNotRunning
        }
        for warmup in 0 ..< Configuration.warmupCycles {
            // The first request can arrive while a cold Release launch is still
            // completing setup and its initial XPC snapshot. Establish readiness
            // outside the measured window, then retain the strict timeout below.
            let timeout: Duration = warmup == 0 ? .seconds(30) : Configuration.iconTimeout
            _ = try requestProductionReopen(processIdentifier: processIdentifier, timeout: timeout)
        }
        var latencies = [Double]()
        for cycle in 1 ... Configuration.measuredCycles {
            let latency = try requestProductionReopen(processIdentifier: processIdentifier)
            latencies.append(latency)
            print(String(format: "cycle=%02d status=OK latency_ms=%.1f", cycle, latency))
            usleep(50000)
        }
        let median = percentile(latencies, 0.50)
        let p95 = percentile(latencies, 0.95)
        let maximum = latencies.max() ?? 0
        let budgetMilliseconds = milliseconds(Configuration.feedbackBudget)
        let passed = p95 <= budgetMilliseconds
        let verdict = passed ? "PASS" : (Configuration.enforceBudget ? "FAIL" : "OBSERVED")
        print(
            String(
                format: "RESULT samples=%d timeouts=0 median_ms=%.1f p95_ms=%.1f max_ms=%.1f feedback_in_250ms=%@ silent_cancellation=false verdict=%@",
                latencies.count,
                median,
                p95,
                maximum,
                passed.description,
                verdict
            )
        )
        exit(passed || !Configuration.enforceBudget ? EXIT_SUCCESS : EXIT_FAILURE)
    }
    guard Configuration.probe == "runtime-smoke" else {
        fputs("error: BARLINE_PERFORMANCE_PROBE must be runtime-smoke or apple-event-reopen\n", stderr)
        exit(2)
    }

    let iconPoint = try barlineIconCenter()

    try ensureClosed(iconPoint: iconPoint)

    for _ in 0 ..< Configuration.warmupCycles {
        _ = try runSingleClick(iconPoint: iconPoint)
    }

    var latencies = [Double]()
    var timeouts = 0

    for cycle in 1 ... Configuration.measuredCycles {
        if let latency = try runSingleClick(iconPoint: iconPoint) {
            latencies.append(latency)
            print(String(format: "cycle=%02d status=OK latency_ms=%.1f", cycle, latency))
        } else {
            timeouts += 1
            print(String(format: "cycle=%02d status=TIMEOUT", cycle))
            try ensureClosed(iconPoint: iconPoint)
        }
    }

    let rapidRetry = try runRapidRetry(iconPoint: iconPoint)
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
