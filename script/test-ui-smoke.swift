import AppKit
import CoreGraphics
import Foundation

enum SmokeFailure: Error, CustomStringConvertible {
    case invalidArguments
    case appNotRunning
    case wrongBundleURL(URL?)
    case noVisibleWindow

    var description: String {
        switch self {
        case .invalidArguments:
            "expected app bundle path and bundle identifier"
        case .appNotRunning:
            "Barline process is not running"
        case .wrongBundleURL:
            "running process did not originate from the expected local build"
        case .noVisibleWindow:
            "Barline exposed no visible standard window after reopen"
        }
    }
}

do {
    guard CommandLine.arguments.count == 3 else { throw SmokeFailure.invalidArguments }
    let expectedURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let bundleIdentifier = CommandLine.arguments[2]
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
        throw SmokeFailure.appNotRunning
    }
    guard app.bundleURL?.standardizedFileURL == expectedURL else {
        throw SmokeFailure.wrongBundleURL(app.bundleURL)
    }

    let records = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[CFString: Any]] ?? []
    let windows = records.compactMap { record -> CGRect? in
        guard (record[kCGWindowOwnerPID] as? NSNumber)?.int32Value == app.processIdentifier else {
            return nil
        }
        guard (record[kCGWindowLayer] as? NSNumber)?.intValue == 0 else { return nil }
        guard let bounds = record[kCGWindowBounds] as? [String: NSNumber] else { return nil }
        guard
            let x = bounds["X"]?.doubleValue,
            let y = bounds["Y"]?.doubleValue,
            let width = bounds["Width"]?.doubleValue,
            let height = bounds["Height"]?.doubleValue
        else { return nil }
        let rectangle = CGRect(x: x, y: y, width: width, height: height)
        return rectangle.width >= 100 && rectangle.height >= 100 ? rectangle : nil
    }
    guard !windows.isEmpty else { throw SmokeFailure.noVisibleWindow }

    let dimensions = windows.map { "\(Int($0.width))x\(Int($0.height))" }.joined(separator: ",")
    print("PASS: local Barline build is running and exposes \(windows.count) visible window(s): \(dimensions)")
} catch {
    fputs("error: UI smoke failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
