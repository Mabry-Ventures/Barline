/// Ownership of deferred work associated with one presentation lifetime.
public struct PresentationEpoch: Sendable {
    public struct Lease: Equatable, Sendable {
        fileprivate let generation: UInt
    }

    public private(set) var generation: UInt = 0

    public init() {}

    public var lease: Lease {
        Lease(generation: generation)
    }

    public mutating func advance() {
        generation &+= 1
    }

    public func owns(_ lease: Lease) -> Bool {
        generation == lease.generation
    }
}
