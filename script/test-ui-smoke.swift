import AppKit
import CoreGraphics
import Foundation

enum SmokeFailure: Error, CustomStringConvertible {
    case invalidArguments
    case appNotRunning
    case wrongBundleURL(URL?)
    case noVisibleSurface

    var description: String {
        switch self {
        case .invalidArguments:
            "expected app bundle path and bundle identifier"
        case .appNotRunning:
            "Barline process is not running"
        case .wrongBundleURL:
            "running process did not originate from the expected local build"
        case .noVisibleSurface:
            "Barline exposed neither a visible standard window nor its status item"
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

    let deadline = Date().addingTimeInterval(3)
    var windows = [CGRect]()
    var records = [[CFString: Any]]()
    repeat {
        records = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] ?? []
        windows = records.compactMap { record -> CGRect? in
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
        if windows.isEmpty {
            usleep(100_000)
        }
    } while windows.isEmpty && Date() < deadline

    let statusItem = records.first { record in
        guard record[kCGWindowName] as? String == "Barline.ControlItem.Visible" else { return false }
        guard let bounds = record[kCGWindowBounds] as? [String: NSNumber] else { return false }
        return (bounds["Width"]?.doubleValue ?? 0) > 0 && (bounds["Height"]?.doubleValue ?? 0) > 0
    }
    guard !windows.isEmpty || statusItem != nil else {
        throw SmokeFailure.noVisibleSurface
    }

    if windows.isEmpty {
        print("PASS: local Barline build is running and exposes its visible Control Center status item")
    } else {
        let dimensions = windows.map { "\(Int($0.width))x\(Int($0.height))" }.joined(separator: ",")
        print("PASS: local Barline build is running and exposes \(windows.count) visible window(s): \(dimensions)")
    }
} catch {
    fputs("error: UI smoke failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
