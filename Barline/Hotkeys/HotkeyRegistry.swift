//
//  HotkeyRegistry.swift
//  Barline
//

import BarlineCore
import Carbon.HIToolbox
import Cocoa
import Combine

/// App-lifetime shared Carbon registration owner. All use is on the main run loop.
@MainActor
final class HotkeyRegistry {
    enum EventKind { case keyUp, keyDown }

    enum RegistrationError: Error {
        case invalid, reserved, conflict, system(OSStatus)

        var message: String {
            switch self {
            case .invalid: "Choose a key with Command, Option, or Control."
            case .reserved: "This shortcut is reserved by macOS."
            case .conflict: "Another Barline action already uses this shortcut."
            case .system: "macOS could not register this shortcut. It may be in use by another app."
            }
        }
    }

    private final class Registration {
        let combination: KeyCombination
        let eventKind: EventKind
        let hotKeyID: EventHotKeyID
        var hotKeyRef: EventHotKeyRef?
        var pendingRemoval = false
        var lastError: RegistrationError?
        let handler: @MainActor () -> Void
        let stateChanged: @MainActor (RegistrationError?) -> Void

        init(
            combination: KeyCombination,
            eventKind: EventKind,
            hotKeyID: EventHotKeyID,
            handler: @escaping @MainActor () -> Void,
            stateChanged: @escaping @MainActor (RegistrationError?) -> Void
        ) {
            self.combination = combination
            self.eventKind = eventKind
            self.hotKeyID = hotKeyID
            self.handler = handler
            self.stateChanged = stateChanged
        }
    }

    private let signature = OSType(1_231_250_720)
    private var eventHandlerRef: EventHandlerRef?
    private var registrations = [UInt32: Registration]()
    private var nextID: UInt32 = 0
    private var cancellables = Set<AnyCancellable>()
    private var menuDepth = 0
    private var recordingTokens = Set<UUID>()
    private var cycle = ShortcutPressCycle()
    var isSuspended: Bool {
        menuDepth > 0 || !recordingTokens.isEmpty
    }

    isolated deinit {
        for registration in registrations.values {
            if let reference = registration.hotKeyRef {
                UnregisterEventHotKey(reference)
            }
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func installIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else { return noErr }
        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            // Carbon's application dispatcher runs synchronously on the main
            // event loop. No event or unsafe pointer crosses an async boundary.
            return MainActor.assumeIsolated {
                Unmanaged<HotkeyRegistry>.fromOpaque(userData).takeUnretainedValue().handle(event)
            }
        }
        let types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            types.count,
            types,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard status == noErr else { return status }
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuDepth += 1
                    self.suspendRegistrations()
                }
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuDepth = max(0, self.menuDepth - 1)
                    self.resumeRegistrations()
                }
            }.store(in: &cancellables)
        return status
    }

    func beginRecording() -> UUID {
        let token = UUID()
        recordingTokens.insert(token)
        suspendRegistrations()
        return token
    }

    func endRecording(_ token: UUID) {
        recordingTokens.remove(token)
        resumeRegistrations()
    }

    func validationError(for combination: KeyCombination, excluding id: UInt32? = nil) -> RegistrationError? {
        guard combination.isValid else { return .invalid }
        guard !combination.isSystemReserved else { return .reserved }
        guard !registrations.contains(where: { $0.key != id && $0.value.combination == combination }) else {
            return .conflict
        }
        return nil
    }

    /// Replacement is transactional: a failed Carbon registration preserves the old registration.
    func register(
        combination: KeyCombination,
        eventKind: EventKind,
        replacing oldID: UInt32? = nil,
        stateChanged: @escaping @MainActor (RegistrationError?) -> Void,
        handler: @escaping @MainActor () -> Void
    ) -> Result<UInt32, RegistrationError> {
        retryPendingRemovals()
        if let error = validationError(for: combination, excluding: oldID) {
            return .failure(error)
        }
        let status = installIfNeeded()
        guard status == noErr else { return .failure(.system(status)) }
        if let oldID, let current = registrations[oldID], current.combination == combination {
            if current.hotKeyRef != nil {
                return .success(oldID)
            }
            let result = registerCarbon(current)
            if let result {
                return .failure(result)
            }
            if isSuspended {
                suspendRegistrations()
            }
            return .success(oldID)
        }
        nextID &+= 1
        while registrations[nextID] != nil {
            nextID &+= 1
        }
        let id = nextID
        let registration = Registration(
            combination: combination,
            eventKind: eventKind,
            hotKeyID: EventHotKeyID(signature: signature, id: id),
            handler: handler,
            stateChanged: stateChanged
        )
        if let error = registerCarbon(registration) {
            return .failure(error)
        }
        // Retain every native reference before any cleanup can fail.
        registrations[id] = registration
        if let oldID {
            if let error = unregister(oldID, retiring: false) {
                // Failed replacement preserves the old action. The provisional
                // action is disabled even if Carbon refuses its cleanup too.
                _ = unregister(id)
                return .failure(error)
            }
        }
        if isSuspended {
            suspendRegistrations()
        }
        return .success(id)
    }

    @discardableResult
    func unregister(_ id: UInt32, retiring: Bool = true) -> RegistrationError? {
        guard let registration = registrations[id] else { return nil }
        if retiring {
            registration.pendingRemoval = true
        }
        _ = cycle.keyUp(id)
        if let reference = registration.hotKeyRef {
            let status = UnregisterEventHotKey(reference)
            guard status == noErr else {
                let error = RegistrationError.system(status)
                if retiring {
                    registration.lastError = error
                    registration.stateChanged(error)
                }
                // Keep ownership so cleanup can retry. Retiring registrations
                // cannot dispatch, including after a failed persistence rollback.
                return error
            }
        }
        registrations.removeValue(forKey: id)
        return nil
    }

    func registrationError(for id: UInt32) -> RegistrationError? {
        registrations[id]?.lastError
    }

    func isAvailable(_ id: UInt32) -> Bool {
        guard let registration = registrations[id], !registration.pendingRemoval else { return false }
        return registration.lastError == nil && (registration.hotKeyRef != nil || isSuspended)
    }

    private func retryPendingRemovals() {
        let pendingIDs = registrations.filter(\.value.pendingRemoval).map(\.key)
        for id in pendingIDs {
            _ = unregister(id)
        }
    }

    private func registerCarbon(_ registration: Registration) -> RegistrationError? {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(registration.combination.key.rawValue),
            UInt32(registration.combination.modifiers.carbonFlags),
            registration.hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            let error = RegistrationError.system(status)
            registration.lastError = error
            return error
        }
        registration.hotKeyRef = reference
        registration.lastError = nil
        return nil
    }

    private func suspendRegistrations() {
        cycle.reset()
        for registration in registrations.values {
            guard let reference = registration.hotKeyRef else { continue }
            let status = UnregisterEventHotKey(reference)
            if status == noErr {
                registration.hotKeyRef = nil
                registration.lastError = nil
            } else {
                registration.lastError = .system(status)
                registration.stateChanged(.system(status))
            }
        }
    }

    private func resumeRegistrations() {
        guard !isSuspended else { return }
        retryPendingRemovals()
        for registration in registrations.values where !registration.pendingRemoval {
            if let reference = registration.hotKeyRef, registration.lastError != nil {
                let status = UnregisterEventHotKey(reference)
                guard status == noErr else {
                    registration.lastError = .system(status)
                    registration.stateChanged(.system(status))
                    continue
                }
                registration.hotKeyRef = nil
            }
            guard registration.hotKeyRef == nil else { continue }
            // Keep failed registrations and their saved assignment visible, never silently discard.
            registration.stateChanged(registerCarbon(registration))
        }
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &id
        )
        guard status == noErr else { return status }
        guard id.signature == signature, let registration = registrations[id.id],
              registration.hotKeyRef != nil, !registration.pendingRemoval,
              registration.lastError == nil,
              !isSuspended else { return OSStatus(eventNotHandledErr) }
        switch Int(GetEventKind(event)) {
        case kEventHotKeyPressed:
            if cycle.keyDown(id.id), registration.eventKind == .keyDown {
                registration.handler()
            }
        case kEventHotKeyReleased:
            if cycle.keyUp(id.id), registration.eventKind == .keyUp {
                registration.handler()
            }
        default: return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}
