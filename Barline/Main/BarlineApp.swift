//
//  BarlineApp.swift
//  Barline
//

import SwiftUI

@main
struct BarlineApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        SettingsWindow(appState: appDelegate.appState)
        PermissionsWindow(appState: appDelegate.appState)
    }
}
