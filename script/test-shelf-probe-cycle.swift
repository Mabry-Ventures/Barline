import Foundation

@main
struct ShelfProbeCycleTests {
    enum ObservationError: Error { case foregroundInterrupted }

    static func main() throws {
        var clicks = 0
        let success = try ShelfProbeCycle.run(
            baselineClosed: { true }, click: { clicks += 1 },
            waitForOpen: { 42 }, waitForClose: { true }
        )
        precondition(success == 42 && clicks == 2)

        clicks = 0
        let openFailure = try ShelfProbeCycle.run(
            baselineClosed: { true }, click: { clicks += 1 },
            waitForOpen: { nil }, waitForClose: { fatalError("must not close an unopened shelf") }
        )
        precondition(openFailure == nil && clicks == 1)

        clicks = 0
        do {
            _ = try ShelfProbeCycle.run(
                baselineClosed: { true }, click: { clicks += 1 },
                waitForOpen: { 42 }, waitForClose: { false }
            )
            fatalError("a missed close must fail the current cycle")
        } catch ShelfProbeCycle.Failure.closeTimedOut {
            precondition(clicks == 2)
        }
        do {
            _ = try ShelfProbeCycle.run(
                baselineClosed: { false }, click: { clicks += 1 },
                waitForOpen: { 42 }, waitForClose: { true }
            )
            fatalError("an unclosed baseline cannot start the next cycle")
        } catch ShelfProbeCycle.Failure.baselineStillOpen {
            precondition(clicks == 2)
        }
        clicks = 0
        do {
            _ = try ShelfProbeCycle.run(
                baselineClosed: { true }, click: { clicks += 1 },
                waitForOpen: { throw ObservationError.foregroundInterrupted },
                waitForClose: { fatalError("must not click again after interrupted observation") }
            )
            fatalError("interrupted opening must propagate separately from timeout")
        } catch ObservationError.foregroundInterrupted {
            precondition(clicks == 1)
        }
        clicks = 0
        do {
            _ = try ShelfProbeCycle.run(
                baselineClosed: { true }, click: { clicks += 1 },
                waitForOpen: { 42 }, waitForClose: { throw ObservationError.foregroundInterrupted }
            )
            fatalError("interrupted closing must propagate separately from timeout")
        } catch ObservationError.foregroundInterrupted {
            precondition(clicks == 2)
        }
        print("PASS: six shelf cycle cases: success, open timeout, close timeout, baseline, interrupted open/close")
    }
}
