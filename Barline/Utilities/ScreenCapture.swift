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

    private static let permissionCache = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    static func checkPermissions() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

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
        guard let capture = try? await BarlineMenuService.Connection.shared.captureBackground(
            displayID: displayID,
            sampleHeight: sampleHeight
        ) else {
            return nil
        }
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
