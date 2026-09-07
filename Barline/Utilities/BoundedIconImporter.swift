//
//  BoundedIconImporter.swift
//  Barline
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// File access and ImageIO decoding are confined to this non-UI actor. Only a
/// small normalized PNG crosses back to Settings, never the original image.
actor BoundedIconImporter {
    static let shared = BoundedIconImporter()
    static let maximumInputBytes = 8 * 1024 * 1024
    static let maximumPixelCount = 40_000_000
    static let maximumDimension = 16384
    static let thumbnailDimension = 72
    static let maximumOutputBytes = 128 * 1024

    enum ImportError: LocalizedError {
        case tooLarge
        case unsupportedImage
        case invalidFile

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                "Choose an image smaller than 8 MB and 40 megapixels."
            case .unsupportedImage:
                "This image could not be read. Choose a PNG, JPEG, HEIC, or another supported image."
            case .invalidFile:
                "Choose a regular image file."
            }
        }
    }

    func load(from url: URL) throws -> Data {
        try Task.checkCancellation()
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ImportError.invalidFile }
        guard let fileSize = values.fileSize, fileSize <= Self.maximumInputBytes else {
            throw ImportError.tooLarge
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // The capped read also covers a file that grows after the metadata check.
        let data = try handle.read(upToCount: Self.maximumInputBytes + 1) ?? Data()
        guard data.count <= Self.maximumInputBytes else { throw ImportError.tooLarge }
        try Task.checkCancellation()
        return try normalizedPNG(from: data)
    }

    func normalizedPNG(from data: Data) throws -> Data {
        try Task.checkCancellation()
        guard data.count <= Self.maximumInputBytes else { throw ImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw ImportError.unsupportedImage }
        guard width <= Self.maximumDimension, height <= Self.maximumDimension,
              width <= Self.maximumPixelCount / height
        else { throw ImportError.tooLarge }
        try Task.checkCancellation()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailDimension,
        ] as CFDictionary) else { throw ImportError.unsupportedImage }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ImportError.unsupportedImage
        }
        // Do not copy source metadata, including location, comments, or filenames.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= Self.maximumOutputBytes else {
            throw ImportError.unsupportedImage
        }
        try Task.checkCancellation()
        return output as Data
    }
}
