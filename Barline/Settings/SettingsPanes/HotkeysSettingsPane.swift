//
//  HotkeysSettingsPane.swift
//  Barline
//

import BarlineCore
import SwiftUI

struct HotkeysSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: HotkeysSettings
    @State private var selectedItemID: MenuBarItemID?
    @State private var itemSnapshot = [MenuBarItem]()

    var body: some View {
        BarlineForm {
            BarlineSection("Menu Bar Sections") {
                hotkeyRecorder(forSection: .hidden)
                hotkeyRecorder(forSection: .alwaysHidden)
            }
            BarlineSection("Menu Bar Items") {
                hotkeyRecorder(forAction: .searchMenuBarItems)
            }
            itemShortcuts
            BarlineSection("Other") {
                hotkeyRecorder(forAction: .enableBarlineShelf)
                hotkeyRecorder(forAction: .toggleApplicationMenus)
            }
        }
        .onReceive(appState.itemManager.$itemCache) { itemSnapshot = $0.managedItems }
    }

    private var itemShortcuts: some View {
        BarlineSection("Open a Menu Bar Item") {
            Text("Assign a shortcut to open an item directly, including hidden items. Shortcuts run once when released.")
                .foregroundStyle(.secondary)
            if let notice = settings.itemShortcutNotice {
                Text(notice).foregroundStyle(.secondary)
            }
            ForEach(settings.itemHotkeys, id: \.itemID) { hotkey in
                if let itemID = hotkey.itemID {
                    HStack {
                        HotkeyRecorder(hotkey: hotkey) {
                            VStack(alignment: .leading) {
                                Text(itemName(itemID))
                                if !availableItems.contains(where: { $0.stableID == itemID }) {
                                    Text("Item unavailable — assignment retained").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Remove") { Task { await settings.removeItemShortcut(hotkey) } }
                            .disabled(hotkey.isSaving)
                    }
                }
            }
            HStack {
                Picker("Item", selection: $selectedItemID) {
                    Text("Choose an item").tag(MenuBarItemID?.none)
                    ForEach(availableItems, id: \.stableID) { item in
                        Text(item.displayName).tag(Optional(item.stableID))
                    }
                }
                Button("Add Shortcut") {
                    if let selectedItemID {
                        settings.addItemShortcut(selectedItemID)
                    }
                    selectedItemID = nil
                }
                .disabled(selectedItemID == nil || settings.itemHotkeys.contains { $0.itemID == selectedItemID })
            }
            .disabled(!settings.itemPreferencesReady || settings.itemHotkeys.count >= ItemShortcutBindings.maximumEntries)
        }
    }

    private var availableItems: [MenuBarItem] {
        var seen = Set<MenuBarItemID>()
        return itemSnapshot.filter {
            !$0.isControlItem && $0.stableID.isPlausiblyStable && seen.insert($0.stableID).inserted
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func itemName(_ itemID: MenuBarItemID) -> String {
        availableItems.first { $0.stableID == itemID }?.displayName ?? itemID.bundleIdentifier
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = settings.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey) {
                switch action {
                case .toggleHiddenSection:
                    Text("Toggle the hidden section")
                case .toggleAlwaysHiddenSection:
                    Text("Toggle the always-hidden section")
                case .searchMenuBarItems:
                    Text("Search menu bar items")
                case .enableBarlineShelf:
                    Text("Enable the Barline Bar")
                case .toggleApplicationMenus:
                    Text("Toggle application menus")
                }
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forSection name: MenuBarSection.Name) -> some View {
        if appState.menuBarManager.section(withName: name)?.isEnabled == true {
            if case .hidden = name {
                hotkeyRecorder(forAction: .toggleHiddenSection)
            } else if case .alwaysHidden = name {
                hotkeyRecorder(forAction: .toggleAlwaysHiddenSection)
            }
        }
    }
}
