//
//  test-bounded-icon-import.swift
//  Barline
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct BoundedIconImportChecks {
    static func main() async throws {
        let importer = BoundedIconImporter()
        let original = try png(width: 600, height: 300)
        let normalized = try await importer.normalizedPNG(from: original)
        guard let source = CGImageSourceCreateWithData(normalized as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == 72,
              properties[kCGImagePropertyPixelHeight] as? Int == 36,
              normalized.count <= BoundedIconImporter.maximumOutputBytes
        else { throw CheckFailure.failed("normalized dimensions and byte bound") }

        try await expectFailure("invalid image") {
            try await importer.normalizedPNG(from: Data("not an image".utf8))
        }
        try await expectFailure("byte limit") {
            try await importer.normalizedPNG(from: Data(count: BoundedIconImporter.maximumInputBytes + 1))
        }
        let oversizedDimensions = try png(width: 16385, height: 1)
        try await expectFailure("dimension limit") {
            try await importer.normalizedPNG(from: oversizedDimensions)
        }
        let oversizedPixels = try png(width: 6500, height: 6500)
        try await expectFailure("pixel limit") {
            try await importer.normalizedPNG(from: oversizedPixels)
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("icon.png")
        try original.write(to: imageURL)
        let fileResult = try await importer.load(from: imageURL)
        guard !fileResult.isEmpty else { throw CheckFailure.failed("regular local file import") }
        try await expectFailure("reject directory") { try await importer.load(from: directory) }
        let oversizedURL = directory.appendingPathComponent("oversized.png")
        try Data(count: BoundedIconImporter.maximumInputBytes + 1).write(to: oversizedURL)
        try await expectFailure("file byte limit") { try await importer.load(from: oversizedURL) }

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await importer.load(from: imageURL)
        }
        do {
            _ = try await cancelled.value
            throw CheckFailure.failed("cancellation")
        } catch is CancellationError {}
        print("PASS: icon normalization, byte/pixel/dimension limits, invalid inputs, bounded file read, cancellation")
    }

    private static func expectFailure(_ name: String, operation: @Sendable () async throws -> Data) async throws {
        do {
            _ = try await operation()
            throw CheckFailure.failed(name)
        } catch is BoundedIconImporter.ImportError {}
    }

    private static func png(width: Int, height: Int) throws -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = context.makeImage() else { throw CheckFailure.failed("fixture image") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw CheckFailure.failed("fixture encoding")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CheckFailure.failed("fixture encoding") }
        return output as Data
    }

    private enum CheckFailure: Error {
        case failed(String)
    }
}
