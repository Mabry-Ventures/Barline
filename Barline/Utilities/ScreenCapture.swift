//
//  ScreenCapture.swift
//  Barline
//

import CoreGraphics
import ImageIO
import os
import ScreenCaptureKit

/// Public permission checks and semantic helper-backed captures.
enum ScreenCapture {
    struct MenuBarBackground {
        let image: CGImage?
        let menuBarBounds: CGRect
    }

    static let permissionDidChangeNotification = Notification.Name("BarlineScreenCapturePermissionDidChange")
    private static let permissionState = OSAllocatedUnfairLock<(decision: Bool?, generation: UInt64)>(
        initialState: (nil, 0)
    )

    static func checkPermissions() -> Bool {
        let result = CGPreflightScreenCaptureAccess()
        let changed = permissionState.withLock { state in
            guard state.decision != result else { return false }
            state.decision = result
            state.generation &+= 1
            return true
        }
        if changed {
            NotificationCenter.default.post(name: permissionDidChangeNotification, object: nil)
        }
        return result
    }

    static func cachedCheckPermissions() -> Bool {
        // Compatibility spelling for existing presentation callers. A TCC
        // decision must never be cached for the lifetime of an accessory app.
        checkPermissions()
    }

    static func requestPermissions() {
        if #available(macOS 15.0, *) {
            SCShareableContent.getWithCompletionHandler { _, _ in }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    static func captureMenuBarBackground(
        displayID: CGDirectDisplayID,
        sampleHeight: CGFloat? = nil
    ) async -> MenuBarBackground? {
        guard checkPermissions() else { return nil }
        let generation = permissionState.withLock { $0.generation }
        guard let capture = try? await BarlineMenuService.Connection.shared.captureBackground(
            displayID: displayID,
            sampleHeight: sampleHeight
        ) else {
            return nil
        }
        guard checkPermissions(), generation == permissionState.withLock({ $0.generation }) else { return nil }
        let image = capture.pngData.flatMap { data -> CGImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return MenuBarBackground(
            image: image,
            menuBarBounds: CGRect(
                x: capture.menuBarBounds.x,
                y: capture.menuBarBounds.y,
                width: capture.menuBarBounds.width,
                height: capture.menuBarBounds.height
            )
        )
    }
}
