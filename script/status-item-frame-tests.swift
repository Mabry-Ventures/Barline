import Foundation
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

@main
enum StatusItemFrameTests {
    static func main() {
        let source = CGRect(x: 100, y: 5, width: 18, height: 24)
        let hosted = CGRect(x: 99, y: 0.5, width: 20, height: 33)
        precondition(StatusItemFrameMatching.matches(source: source, hosted: source))
        precondition(StatusItemFrameMatching.matches(source: source, hosted: hosted))
        precondition(!StatusItemFrameMatching.matches(source: source, hosted: hosted.offsetBy(dx: 2, dy: 0)))
        precondition(!StatusItemFrameMatching.matches(source: source, hosted: hosted.offsetBy(dx: 0, dy: 2)))
        precondition(!StatusItemFrameMatching.matches(source: source, hosted: CGRect(x: 98, y: 5, width: 22, height: 24)))
        precondition(!StatusItemFrameMatching.matches(source: .zero, hosted: hosted))
        precondition(!StatusItemFrameMatching.matches(source: source, hosted: CGRect(x: Double.nan, y: 0, width: 20, height: 33)))
        precondition(!StatusItemFrameMatching.matches(source: source, hosted: CGRect(x: 0, y: 0, width: 120, height: 33)))
        print("PASS: 8 status-item hosting geometry regressions")
    }
}
