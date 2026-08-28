//
//  DarwinNotificationObserver.swift
//  Barline
//

import CoreFoundation
import Foundation

/// Darwin notifications carry no command data. They only prompt Barline to
/// rescan its durable App Group command inbox.
final class DarwinNotificationObserver: @unchecked Sendable {
    private let center = CFNotificationCenterGetDarwinNotifyCenter()
    private let name: CFNotificationName
    private let handler: @Sendable () -> Void

    init(name: String, handler: @escaping @Sendable () -> Void) {
        self.name = CFNotificationName(name as CFString)
        self.handler = handler
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let token = Unmanaged<DarwinNotificationObserver>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                token.handler()
            },
            self.name.rawValue,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(center, Unmanaged.passUnretained(self).toOpaque(), name, nil)
    }
}
