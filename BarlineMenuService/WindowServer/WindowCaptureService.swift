//
//  WindowCaptureService.swift
//  BarlineMenuService
//

import AppKit
import CoreGraphics
import Foundation

enum WindowCaptureService {
    private typealias CaptureFunction = @convention(c) (
        CGRect,
        CFArray,
        CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    private static let resolver = DynamicSymbolResolver()

    static func capturePNG(
        windowIDs: [CGWindowID],
        screenBounds: CGRect?,
        options: UInt32
    ) -> Data? {
        guard
            let array = createWindowArray(windowIDs),
            let capture = resolver.resolve(
                "CGWindowListCreateImageFromArray",
                as: CaptureFunction.self
            ),
            let image = capture(
                screenBounds ?? .null,
                array,
                CGWindowImageOption(rawValue: options)
            )?.takeRetainedValue()
        else {
            return nil
        }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func createWindowArray(_ windowIDs: [CGWindowID]) -> CFArray? {
        var pointers: [UnsafeRawPointer?] = windowIDs.compactMap {
            UnsafeRawPointer(bitPattern: UInt($0))
        }
        guard !pointers.isEmpty else {
            return nil
        }
        return CFArrayCreate(nil, &pointers, pointers.count, nil)
    }
}
