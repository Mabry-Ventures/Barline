#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appending(path: "Barline/Resources/Assets.xcassets/AppIcon.appiconset")
let control = root.appending(path: "Barline/Resources/Assets.xcassets/ControlItemImages/BarlineControl")
let resources = root.appending(path: "Resources")

func writePNG(size: Int, to url: URL, draw: (CGRect) -> Void) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    CGRect(x: 0, y: 0, width: size, height: size).fill()
    draw(CGRect(x: 0, y: 0, width: size, height: size))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

func drawAppIcon(in rect: CGRect) {
    let scale = rect.width / 1024
    let background = NSBezierPath(
        roundedRect: CGRect(x: 64 * scale, y: 64 * scale, width: 896 * scale, height: 896 * scale),
        xRadius: 210 * scale,
        yRadius: 210 * scale
    )
    let gradient = NSGradient(colors: [
        NSColor(red: 0.19, green: 0.72, blue: 0.85, alpha: 1),
        NSColor(red: 0.15, green: 0.36, blue: 0.85, alpha: 1),
    ])
    gradient?.draw(in: background, angle: -50)

    NSColor.white.setFill()
    for (x, y, width) in [(210.0, 648.0, 604.0), (210, 474, 470), (210, 300, 336)] {
        NSBezierPath(
            roundedRect: CGRect(x: x * scale, y: y * scale, width: width * scale, height: 76 * scale),
            xRadius: 38 * scale,
            yRadius: 38 * scale
        ).fill()
    }
    NSBezierPath(ovalIn: CGRect(x: 770 * scale, y: 468 * scale, width: 88 * scale, height: 88 * scale)).fill()
    NSBezierPath(ovalIn: CGRect(x: 636 * scale, y: 294 * scale, width: 88 * scale, height: 88 * scale)).fill()
}

func drawControlIcon(in rect: CGRect, filled: Bool) {
    let scale = rect.width / 32
    let color = NSColor.black
    color.setStroke()
    color.setFill()
    let lineWidth = max(1, 2 * scale)
    for (y, width) in [(23.0, 22.0), (16.0, 17.0), (9.0, 12.0)] {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: 5 * scale, y: y * scale))
        path.line(to: CGPoint(x: (5 + width) * scale, y: y * scale))
        path.stroke()
    }
    let marker = NSBezierPath(ovalIn: CGRect(x: 23 * scale, y: 13 * scale, width: 6 * scale, height: 6 * scale))
    if filled {
        marker.fill()
    } else {
        marker.lineWidth = lineWidth
        marker.stroke()
    }
}

let appSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in appSizes {
    try writePNG(size: size, to: catalog.appending(path: name), draw: drawAppIcon)
}
try writePNG(size: 1024, to: resources.appending(path: "BarlineIcon.png"), draw: drawAppIcon)
try writePNG(
    size: 64,
    to: control.appending(path: "BarlineControlFill.imageset/BarlineControlFill.png")
) { drawControlIcon(in: $0, filled: true) }
try writePNG(
    size: 64,
    to: control.appending(path: "BarlineControlStroke.imageset/BarlineControlStroke.png")
) { drawControlIcon(in: $0, filled: false) }

print("Generated Barline app and menu bar control icons.")
