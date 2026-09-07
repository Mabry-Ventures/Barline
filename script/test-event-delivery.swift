import Foundation

/// Exercises the production delivery state without creating a tap or posting
/// an event. These are synchronization tests, not a GUI-delivery certificate.
@main
private enum EventDeliveryTests {
    static func main() {
        concurrentCallbacksDispatchOnlyOnce()
        completionSuppressesLateDispatch()
        inFlightDispatchPrecedesCompletion()
        print("PASS: production event delivery synchronization (3 tests; no taps or events)")
    }

    private static func concurrentCallbacksDispatchOnlyOnce() {
        let delivery = HelperEventDelivery()
        let posted = LockedLog()
        let callbacks = DispatchGroup()
        for _ in 0 ..< 128 {
            callbacks.enter()
            DispatchQueue.global().async {
                delivery.dispatchOnceWhilePending { posted.append("post") }
                callbacks.leave()
            }
        }
        require(callbacks.wait(timeout: .now() + 3) == .success, "concurrent callbacks finish within budget")
        require(posted.values == ["post"], "concurrent callbacks post exactly once")
        delivery.finish()
    }

    private static func completionSuppressesLateDispatch() {
        let delivery = HelperEventDelivery()
        let posted = LockedLog()
        delivery.finish()
        let callbacks = DispatchGroup()
        for _ in 0 ..< 32 {
            callbacks.enter()
            DispatchQueue.global().async {
                delivery.dispatchOnceWhilePending { posted.append("late-post") }
                callbacks.leave()
            }
        }
        require(callbacks.wait(timeout: .now() + 3) == .success, "late callbacks finish within budget")
        require(posted.values.isEmpty, "completed delivery suppresses every late post")
    }

    private static func inFlightDispatchPrecedesCompletion() {
        let delivery = HelperEventDelivery()
        let events = LockedLog()
        let enteredPost = DispatchSemaphore(value: 0)
        let releasePost = DispatchSemaphore(value: 0)
        let completionRequested = DispatchSemaphore(value: 0)
        let completionReturned = DispatchSemaphore(value: 0)
        let dispatchReturned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            delivery.dispatchOnceWhilePending {
                events.append("post-started")
                enteredPost.signal()
                require(releasePost.wait(timeout: .now() + 3) == .success, "post release arrives within budget")
                events.append("post-enqueued")
            }
            dispatchReturned.signal()
        }
        require(enteredPost.wait(timeout: .now() + 3) == .success, "dispatch enters the protected post")
        DispatchQueue.global().async {
            completionRequested.signal()
            delivery.finish()
            events.append("completion-returned")
            completionReturned.signal()
        }
        require(completionRequested.wait(timeout: .now() + 3) == .success, "completion attempt starts")
        // The post closure deliberately stays in flight while another thread
        // completes. A completion must not let cleanup-up overtake this down.
        require(completionReturned.wait(timeout: .now() + .milliseconds(100)) == .timedOut,
                "completion cannot return while the post closure is in flight")
        releasePost.signal()
        require(dispatchReturned.wait(timeout: .now() + 3) == .success, "dispatch returns after enqueue")
        require(completionReturned.wait(timeout: .now() + 3) == .success, "completion returns after dispatch")
        require(events.values == ["post-started", "post-enqueued", "completion-returned"],
                "post enqueue precedes completion and cleanup")
        delivery.dispatchOnceWhilePending { events.append("forbidden-replay") }
        require(events.values.count == 3, "completed dispatch cannot replay")
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
    }
}

private final class LockedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [String]()

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }
}
