//
//  AppDelegate.swift
//  Barline
//

import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The shared app state.
    let appState = AppState()

    #if DEBUG
        private static let runtimeSmokeToggleNotification = Notification.Name(
            "com.mabryventures.Barline.runtime-smoke.toggle-shelf"
        )
    #endif

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_: Notification) {
        // Initial chore work.
        NSSplitViewItem.swizzle()
        MigrationManager(appState: appState).migrateAll()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Hide the main menu's items to add additional space to the
        // menu bar when we are the focused app.
        for item in NSApp.mainMenu?.items ?? [] {
            item.isHidden = true
        }

        // Allow hiding the mouse while the app is in the background
        // to make menu bar item movement less jarring.
        Task {
            await BarlineMenuService.Connection.shared.configureCursorInBackground(true)
        }

        #if DEBUG
            // Don't perform setup if running as a preview.
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                return
            }

            // Runtime smoke tests exercise Barline's own UI without depending on
            // host-specific TCC grants. Release builds never include this path.
            if CommandLine.arguments.contains("--barline-runtime-smoke") {
                DistributedNotificationCenter.default().addObserver(
                    self,
                    selector: #selector(toggleShelfForRuntimeSmoke),
                    name: Self.runtimeSmokeToggleNotification,
                    object: nil
                )
                appState.performSetup(hasPermissions: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.openSettingsWindow()
                }
                return
            }
        #endif

        // Depending on the permissions state, either perform setup
        // or prompt to grant permissions.
        switch appState.permissions.permissionsState {
        case .hasAll:
            appState.permissions.logger.debug("Passed all permissions checks")
            appState.performSetup(hasPermissions: true)
        case .hasRequired:
            appState.permissions.logger.debug("Passed required permissions checks")
            appState.performSetup(hasPermissions: true)
        case .missing:
            appState.permissions.logger.debug("Failed required permissions checks")
            appState.performSetup(hasPermissions: false)
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        Logger.default.debug("Handling reopen")
        openSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if
            sender.isActive,
            sender.activationPolicy() != .accessory,
            appState.navigationState.isAppFrontmost
        {
            Logger.default.debug("All windows closed - deactivating with accessory activation policy")
            appState.deactivate(withPolicy: .accessory)
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    // MARK: Other Methods

    /// Opens the settings window and activates the app.
    @objc func openSettingsWindow() {
        // Delay makes this more reliable for some reason.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [appState] in
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }

    #if DEBUG
        /// Gives a separate local probe a deterministic activation path without
        /// adding any behavior to Release builds.
        @objc private func toggleShelfForRuntimeSmoke() {
            appState.menuBarManager.section(withName: .visible)?.toggle()
        }
    #endif
}
