import Foundation

/// Executes a cancellable observation on a background queue and provides one
/// synchronized result to the caller.
final class ConcurrentObservation<Value: Sendable>: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var outcome: Result<Value, Error>?
    private var cancelled = false

    init(
        qos: DispatchQoS.QoSClass = .userInteractive,
        operation: @escaping @Sendable (_ isCancelled: @escaping @Sendable () -> Bool) throws -> Value
    ) {
        group.enter()
        DispatchQueue.global(qos: qos).async { [self] in
            let result = Result {
                try operation { [self] in
                    lock.withLock { cancelled }
                }
            }
            lock.withLock {
                outcome = result
            }
            group.leave()
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
        }
    }

    func value() throws -> Value {
        group.wait()
        let result = lock.withLock { outcome }
        guard let result else {
            preconditionFailure("ConcurrentObservation completed without a result")
        }
        return try result.get()
    }
}
