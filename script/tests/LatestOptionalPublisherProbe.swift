import Combine
import Foundation

/// Exercises the production operator without launching AppKit or taking focus.
@main
enum LatestOptionalPublisherProbe {
    final class Owner {
        let values: CurrentValueSubject<Int?, Never>
        init(_ value: Int?) {
            values = CurrentValueSubject(value)
        }
    }

    static func main() {
        let root = CurrentValueSubject<Owner?, Never>(nil)
        let old = Owner(1)
        let current = Owner(2)
        var latest: Int?
        var events = 0
        var subscriptions = 0
        var cancellations = 0
        let observation = root.latestOptionalValue(on: ImmediateScheduler.shared) { owner in
            owner.values.handleEvents(
                receiveSubscription: { _ in subscriptions += 1 },
                receiveCancel: { cancellations += 1 }
            ).eraseToAnyPublisher()
        }.sink { latest = $0; events += 1 }

        precondition(events == 1 && latest == nil, "initial detach must clear geometry")
        root.send(old)
        precondition(latest == 1 && subscriptions == 1)
        root.send(current)
        precondition(latest == 2 && cancellations == 1)
        let afterReplacement = events
        old.values.send(99)
        old.values.send(nil)
        precondition(latest == 2 && events == afterReplacement, "superseded owner changed geometry")
        current.values.send(3)
        precondition(latest == 3)
        root.send(nil)
        precondition(latest == nil && cancellations == 2, "detach retained old geometry")
        let afterDetach = events
        current.values.send(88)
        precondition(latest == nil && events == afterDetach)
        root.send(current)
        precondition(latest == 88 && subscriptions == 3)
        observation.cancel()
        precondition(cancellations == 3)
        print("PASS: initial nil, replacement, old update, old nil, live update, detach, detached update, reattach, cancellation")

        // Reproduce the former flatMap/removeNil failure independently: an old
        // window remains subscribed after replacement and nil never clears it.
        let legacyRoot = CurrentValueSubject<Owner?, Never>(nil)
        var legacyValue: Int?
        let legacy = legacyRoot.compactMap(\.self).flatMap(\.values)
            .sink { legacyValue = $0 }
        legacyRoot.send(old)
        legacyRoot.send(current)
        old.values.send(99)
        precondition(legacyValue == 99, "legacy regression setup did not reproduce")
        legacyRoot.send(nil)
        precondition(legacyValue == 99)
        legacy.cancel()
        print("PASS: legacy stale-owner overwrite and nil-retention reproduced")
        queuedDelivery()
        duplicateOwners()
    }

    static func queuedDelivery() {
        let queue = DispatchQueue(label: "barline.qualification.latest-owner")
        let root = CurrentValueSubject<Owner?, Never>(nil)
        let old = Owner(1)
        let current = Owner(2)
        var received = [Int?]()
        var lateScheduled = [Int?]()
        queue.suspend()
        let safe = root.latestOptionalValue(on: queue) { $0.values.eraseToAnyPublisher() }
            .sink { received.append($0) }
        // Scheduling downstream of the switch lets already queued stale values
        // escape cancellation; retain this counterexample in the regression.
        let unsafe = root.latestOptionalValue(on: ImmediateScheduler.shared) { $0.values.eraseToAnyPublisher() }
            .receive(on: queue)
            .sink { lateScheduled.append($0) }
        root.send(old)
        old.values.send(99)
        root.send(current)
        root.send(nil)
        queue.resume()
        queue.sync {}
        precondition(received.count == 1 && received[0] == nil, "queued superseded values escaped cancellation")
        precondition(lateScheduled.contains(99), "queued legacy counterexample did not reproduce")
        safe.cancel()
        unsafe.cancel()
        print("PASS: queued old/current values rejected after detach; downstream-scheduling regression reproduced")
    }

    static func duplicateOwners() {
        let root = CurrentValueSubject<Owner?, Never>(nil)
        let owner = Owner(1)
        var subscriptions = 0
        var configurations = 0
        let observation = root.handleEvents(receiveOutput: { value in
            if value != nil {
                configurations += 1
            }
        }).removeDuplicates { $0 === $1 }
            .latestOptionalValue(on: ImmediateScheduler.shared) { owner in
                owner.values.handleEvents(receiveSubscription: { _ in subscriptions += 1 })
                    .eraseToAnyPublisher()
            }.sink { _ in }
        root.send(owner)
        root.send(owner)
        root.send(owner)
        precondition(subscriptions == 1, "same-owner publication duplicated subscriptions")
        precondition(configurations == 3, "reconnected button must still reconfigure its action")
        root.send(nil)
        root.send(owner)
        precondition(subscriptions == 2)
        observation.cancel()
        print("PASS: repeated current owner reconfigures but subscribes once; detach/reattach subscribes again")
    }
}
