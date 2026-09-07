import Foundation

@main
struct ShelfProbeCycleTests {
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
        print("PASS: shelf probe success, opening failure, missed close, and unclosed baseline")
    }
}
