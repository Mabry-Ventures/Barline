import Foundation
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// macOS 26 status hosting can widen the source AX button by two points and
/// change its height. Match centers and width, never a window title alone.
enum StatusItemFrameMatching {
    static func matches(source: CGRect, hosted: CGRect) -> Bool {
        for rect in [source, hosted] {
            guard [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite),
                  rect.width > 0, rect.width < 100, rect.height > 0, rect.height < 100 else { return false }
        }
        return abs(source.midX - hosted.midX) <= 1 &&
            abs(source.midY - hosted.midY) <= 1 &&
            abs(source.width - hosted.width) <= 2
    }
}
