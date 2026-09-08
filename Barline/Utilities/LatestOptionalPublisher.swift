//
//  LatestOptionalPublisher.swift
//  Barline
//

import Combine

extension Publisher where Failure == Never {
    /// Observe only the current optional owner, publishing nil when it detaches.
    /// Delivery is scheduled inside each switched stream so cancellation also
    /// rejects superseded values already queued for the consumer's executor.
    func latestOptionalValue<Owner, Value>(
        on scheduler: some Scheduler,
        _ transform: @escaping (Owner) -> AnyPublisher<Value?, Never>
    ) -> AnyPublisher<Value?, Never> where Output == Owner? {
        map { owner in
            (owner.map(transform) ?? Just<Value?>(nil).eraseToAnyPublisher())
                .receive(on: scheduler)
                .eraseToAnyPublisher()
        }
        .switchToLatest()
        .eraseToAnyPublisher()
    }
}
