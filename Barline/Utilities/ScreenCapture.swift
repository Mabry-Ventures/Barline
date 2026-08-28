//
//  ScreenCapture.swift
//  Barline
//

import CoreGraphics
import Darwin
import os
import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {
    private static let permissionCache = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    // MARK: Permissions

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    static func checkPermissions() -> Bool {
        for windowID in Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace]) {
            guard
                let window = WindowInfo(windowID: windowID),
                window.owningApplication != .current // Skip windows we own.
            else {
                continue
            }
            return window.title != nil
        }
        // CGPreflightScreenCaptureAccess() only returns an initial value,
        // but we can use it as a fallback.
        return CGPreflightScreenCaptureAccess()
    }

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    ///
    /// This function caches its initial result and returns it on subsequent
    /// calls. Pass `true` to the `reset` parameter to replace the cached
    /// result with a newly computed value.
    static func cachedCheckPermissions(reset: Bool = false) -> Bool {
        permissionCache.withLock { cachedResult in
            if !reset, let cachedResult {
                return cachedResult
            }
            let result = checkPermissions()
            cachedResult = result
            return result
        }
    }

    /// Requests screen capture permissions.
    static func requestPermissions() {
        if #available(macOS 15.0, *) {
            // CGRequestScreenCaptureAccess() is broken on macOS 15. We can
            // try accessing SCShareableContent to trigger a request if the
            // user doesn't have permissions.
            // TODO: Find out if we still need this as of macOS 26.
            SCShareableContent.getWithCompletionHandler { _, _ in }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: Capture Window(s)

    /// Captures a composite image of an array of windows.
    ///
    /// The windows are composited from front to back, according to the order
    /// of the `windowIDs` parameter.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        guard let array = Bridging.createCGWindowArray(with: windowIDs) else {
            return nil
        }
        let bounds = screenBounds ?? .null
        // ScreenCaptureKit cannot capture offscreen menu bar items. Resolve the
        // obsolete CoreGraphics entry point dynamically so its removal disables
        // image capture instead of preventing Barline from launching.
        typealias CaptureFunction = @convention(c) (
            CGRect,
            CFArray,
            CGWindowImageOption
        ) -> Unmanaged<CGImage>?

        guard
            let handle = dlopen(
                "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                RTLD_LAZY | RTLD_LOCAL
            )
        else {
            return nil
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "CGWindowListCreateImageFromArray") else {
            return nil
        }
        let capture = unsafeBitCast(symbol, to: CaptureFunction.self)
        return capture(bounds, array, option)?.takeRetainedValue()
    }

    /// Captures an image of a window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the window.
    ///   - option: Options that specify which parts of the window are captured.
    static func captureWindow(with windowID: CGWindowID, screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        captureWindows(with: [windowID], screenBounds: screenBounds, option: option)
    }
}
