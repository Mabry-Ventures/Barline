//
//  HotkeysSettingsPane.swift
//  Barline
//

import SwiftUI

struct HotkeysSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: HotkeysSettings

    var body: some View {
        BarlineForm {
            BarlineSection("Menu Bar Sections") {
                hotkeyRecorder(forSection: .hidden)
                hotkeyRecorder(forSection: .alwaysHidden)
            }
            BarlineSection("Menu Bar Items") {
                hotkeyRecorder(forAction: .searchMenuBarItems)
            }
            BarlineSection("Other") {
                hotkeyRecorder(forAction: .enableBarlineShelf)
                hotkeyRecorder(forAction: .toggleApplicationMenus)
            }
        }
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
