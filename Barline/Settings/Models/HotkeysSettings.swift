//
//  HotkeysSettings.swift
//  Barline
//

import BarlineCore
import Cocoa
import Combine
import Foundation
import OSLog

/// Model for the app's Hotkeys settings.
@MainActor
final class HotkeysSettings: ObservableObject {
    /// The app's hotkey registry.
    let registry = HotkeyRegistry()

    @Published private(set) var itemHotkeys = [Hotkey]()
    @Published private(set) var itemPreferencesReady = false
    @Published private(set) var itemShortcutNotice: String?
    private let itemPreferences = ItemShortcutPreferences()
    private var itemActivationTask: Task<Void, Never>?
    private var itemBindings = ItemShortcutBindings()

    /// The app's hotkeys.
    let hotkeys = HotkeyAction.allCases.map { action in
        Hotkey(action: action)
    }

    /// Encoder for properties.
    private let encoder = JSONEncoder()

    /// Decoder for properties.
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        for hotkey in hotkeys {
            hotkey.performSetup(with: appState)
            configureValidation(for: hotkey)
        }
        loadInitialState()
        configureCancellables()
        Task { await loadItemShortcuts() }
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        guard
            let dictionary = Defaults.dictionary(forKey: .hotkeys) as? [String: Data],
            !dictionary.isEmpty
        else {
            return
        }
        for hotkey in hotkeys {
            guard let data = dictionary[hotkey.action.rawValue] else {
                continue
            }
            do {
                if let keyCombination = try decoder.decode(KeyCombination?.self, from: data) {
                    hotkey.load(keyCombination)
                }
            } catch {
                Logger.serialization.error("Error decoding hotkey: \(PrivacySafeDiagnostics.errorCode(error), privacy: .public)")
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        for hotkey in hotkeys {
            hotkey.$keyCombination
                .encode(encoder: encoder)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    if case let .failure(error) = completion {
                        Logger.serialization.error("Error encoding hotkey: \(PrivacySafeDiagnostics.errorCode(error), privacy: .public)")
                    }
                } receiveValue: { data in
                    withMutableCopy(of: Defaults.dictionary(forKey: .hotkeys) ?? [:]) { dictionary in
                        dictionary[hotkey.action.rawValue] = data
                        Defaults.set(dictionary, forKey: .hotkeys)
                    }
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Returns the hotkey with the given action.
    func hotkey(withAction action: HotkeyAction) -> Hotkey? {
        hotkeys.first { $0.action == action }
    }

    private func configureValidation(for hotkey: Hotkey) {
        hotkey.validateAssignment = { [weak self, weak hotkey] combination in
            guard let self, let hotkey, let combination else { return nil }
            if (hotkeys + itemHotkeys).contains(where: { $0 !== hotkey && $0.keyCombination == combination }) {
                return "Another Barline action already uses this shortcut."
            }
            return nil
        }
    }

    private func loadItemShortcuts() async {
        do {
            itemBindings = try await itemPreferences.load()
            for entry in itemBindings.entries {
                addItemShortcut(entry.itemID, combination: KeyCombination(chord: entry.chord))
            }
            itemPreferencesReady = true
        } catch {
            itemShortcutNotice = "Saved item shortcuts could not be read. The original file has been preserved."
        }
    }

    func addItemShortcut(_ itemID: MenuBarItemID, combination: KeyCombination? = nil) {
        guard let appState, !itemHotkeys.contains(where: { $0.itemID == itemID }),
              itemHotkeys.count < ItemShortcutBindings.maximumEntries else { return }
        let hotkey = Hotkey(itemID: itemID, keyCombination: combination)
        hotkey.saveItemAssignment = { [weak self] combination in
            guard let self, itemPreferencesReady else { throw ItemShortcutPreferences.StoreError.unavailable }
            itemBindings = try await itemPreferences.setChord(combination?.portableChord, for: itemID)
        }
        hotkey.activateItem = { [weak self] in self?.activateItemShortcut(itemID) }
        configureValidation(for: hotkey)
        itemHotkeys.append(hotkey)
        hotkey.performSetup(with: appState)
    }

    func removeItemShortcut(_ hotkey: Hotkey) async {
        guard await hotkey.requestChange(nil) else { return }
        hotkey.disable()
        itemHotkeys.removeAll { $0 === hotkey }
    }

    private func activateItemShortcut(_ itemID: MenuBarItemID) {
        guard itemActivationTask == nil, !registry.isSuspended, let appState else { return }
        guard appState.permissions.accessibility.hasPermission else {
            itemShortcutNotice = "Accessibility permission is required to open an item. Enable it in Advanced settings."
            NSSound.beep()
            return
        }
        itemActivationTask = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            defer { itemActivationTask = nil }
            // A release event can precede modifier release. Never inject modified clicks or queue indefinitely.
            for _ in 0 ..< 30 {
                if NSEvent.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) {
                    break
                }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
            guard !Task.isCancelled, !registry.isSuspended,
                  NSEvent.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift])
            else {
                itemShortcutNotice = "Release the modifier keys, then try the shortcut again."
                return
            }
            appState.menuBarManager.searchPanel.close()
            appState.menuBarManager.section(withName: .hidden)?.hide()
            appState.menuBarManager.section(withName: .alwaysHidden)?.hide()
            let outcome = await appState.itemManager.activateItem(itemID, with: .left)
            if outcome == .failed {
                itemShortcutNotice = "This item is unavailable or busy. Close any open menu and try again."
                NSSound.beep()
            } else {
                itemShortcutNotice = nil
            }
        }
    }
}
