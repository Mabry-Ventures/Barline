/// A failed close must never be accepted as a successful sample: the next click
/// would close the previous shelf and be misreported as an opening failure.
enum ShelfProbeCycle {
    enum Failure: Error, Equatable {
        case baselineStillOpen
        case closeTimedOut
    }

    static func run(
        baselineClosed: () -> Bool,
        click: () throws -> Void,
        waitForOpen: () -> Double?,
        waitForClose: () -> Bool
    ) throws -> Double? {
        guard baselineClosed() else { throw Failure.baselineStillOpen }
        try click()
        guard let latency = waitForOpen() else { return nil }
        try click()
        guard waitForClose() else { throw Failure.closeTimedOut }
        return latency
    }
}
