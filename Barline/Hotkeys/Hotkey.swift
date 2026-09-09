//
//  Hotkey.swift
//  Barline
//

import BarlineCore
import Combine
import Foundation

/// One saved assignment and its live registration status.
@MainActor
final class Hotkey: ObservableObject {
    @Published private(set) var keyCombination: KeyCombination?
    @Published private(set) var assignmentError: String?
    @Published private(set) var liveRegistrationError: String?
    @Published private(set) var isSaving = false

    let action: HotkeyAction
    let itemID: MenuBarItemID?
    var saveItemAssignment: ((KeyCombination?) async throws -> Void)?
    var activateItem: (() -> Void)?
    var validateAssignment: ((KeyCombination?) -> String?)?

    private weak var registry: HotkeyRegistry?
    private weak var appState: AppState?
    private var listener: Listener?

    var registrationError: String? {
        assignmentError ?? liveRegistrationError
    }

    var isEnabled: Bool {
        guard let id = listener?.id else { return false }
        return registry?.isAvailable(id) == true
    }

    init(action: HotkeyAction, keyCombination: KeyCombination? = nil) {
        self.action = action
        itemID = nil
        self.keyCombination = keyCombination
    }

    init(itemID: MenuBarItemID, keyCombination: KeyCombination? = nil) {
        action = .searchMenuBarItems
        self.itemID = itemID
        self.keyCombination = keyCombination
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        registry = appState.settings.hotkeys.registry
        enable()
    }

    /// Load saved intent even when its system registration is currently unavailable.
    func load(_ combination: KeyCombination) {
        keyCombination = combination
        enable()
    }

    func enable() {
        assignmentError = nil
        if let error = replaceRegistration(with: keyCombination) {
            liveRegistrationError = error
        }
    }

    @discardableResult
    func disable() -> String? {
        if let error = listener?.invalidate() {
            liveRegistrationError = error.message
            return error.message
        }
        listener = nil
        liveRegistrationError = nil
        return nil
    }

    func beginRecording() -> UUID? {
        registry?.beginRecording()
    }

    func endRecording(_ token: UUID) {
        registry?.endRecording(token)
    }

    /// Keep the old assignment on registration or persistence failure.
    func requestChange(_ combination: KeyCombination?) async -> Bool {
        guard !isSaving else { return false }
        if let error = validateAssignment?(combination) {
            assignmentError = error
            return false
        }
        let old = keyCombination
        if let error = replaceRegistration(with: combination) {
            assignmentError = error
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await saveItemAssignment?(combination)
            keyCombination = combination
            // A resume-registration failure may have arrived during the file
            // write. Saving clears only the edit error, never the live status.
            assignmentError = nil
            return true
        } catch {
            let rollbackError = replaceRegistration(with: old)
            if rollbackError != nil {
                disable()
            }
            assignmentError = rollbackError ?? "The shortcut could not be saved. Your previous assignment was kept."
            return false
        }
    }

    private func replaceRegistration(with combination: KeyCombination?) -> String? {
        guard let combination else { return disable() }
        guard let registry else { return "Shortcuts are not ready yet." }
        let result = registry.register(
            combination: combination,
            eventKind: itemID == nil ? .keyDown : .keyUp,
            replacing: listener?.id,
            stateChanged: { [weak self] error in
                self?.liveRegistrationError = error?.message
            },
            handler: { [weak self] in
                guard let self, !self.isSaving, let appState else { return }
                if itemID != nil {
                    activateItem?()
                } else {
                    action.perform(appState: appState)
                }
            }
        )
        switch result {
        case let .failure(error): return error.message
        case let .success(id):
            if let listener {
                listener.id = id
            } else {
                listener = Listener(registry: registry, id: id)
            }
            liveRegistrationError = registry.registrationError(for: id)?.message
            return nil
        }
    }

    @MainActor
    private final class Listener {
        private weak var registry: HotkeyRegistry?
        var id: UInt32?

        init(registry: HotkeyRegistry, id: UInt32) {
            self.registry = registry
            self.id = id
        }

        isolated deinit { _ = invalidate() }

        func invalidate() -> HotkeyRegistry.RegistrationError? {
            if let id {
                if let error = registry?.unregister(id) {
                    return error
                }
            }
            id = nil
            return nil
        }
    }
}

extension Hotkey: @MainActor Equatable {
    static func == (lhs: Hotkey, rhs: Hotkey) -> Bool {
        lhs.keyCombination == rhs.keyCombination && lhs.action == rhs.action && lhs.itemID == rhs.itemID
    }
}

extension Hotkey: @MainActor Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCombination)
        hasher.combine(action)
        hasher.combine(itemID)
    }
}
