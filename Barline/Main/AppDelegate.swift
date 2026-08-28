//
//  AppDelegate.swift
//  Barline
//

import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let reopenRecoveryGenerationKey = "ReopenRecoveryGeneration"
    private static let reopenRecoverySucceededKey = "ReopenRecoverySucceeded"
    /// The shared app state.
    let appState = AppState()

    /// Coalesces repeated requests to activate the settings window.
    private var settingsOpenTask: Task<Void, Never>?

    /// Prevents bursts of reopen events from starting overlapping XPC refreshes.
    private var reopenRecoveryTask: Task<Void, Never>?

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
                appState.performSetup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.openSettingsWindow()
                }
                return
            }
        #endif

        // The settings, saved profiles, search metadata, and diagnostics remain
        // available without Accessibility. Features that manage other apps'
        // status items request that grant only when the user chooses them.
        appState.performSetup()
        if appState.permissions.permissionsState == .missing {
            appState.permissions.logger.debug("Starting in degraded mode without Accessibility")
            openSettingsWindow()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        Logger.default.debug("Handling reopen")
        // A reopen is also a safe recovery opportunity for the compatibility
        // backend. This keeps the app process alive while replacing an
        // interrupted XPC helper before the user performs another action.
        if reopenRecoveryTask == nil {
            reopenRecoveryTask = Task { [weak self] in
                guard let self else {
                    return
                }
                defer { reopenRecoveryTask = nil }
                var succeeded = true
                do {
                    _ = try await appState.compatibilityCoordinator.refresh()
                } catch {
                    succeeded = false
                    Logger.default.error("Compatibility refresh on reopen failed: \(error)")
                }
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
                appState.activate(withPolicy: .regular)
                appState.openWindow(.settings)
                let visibilityDeadline = ContinuousClock.now + .seconds(1)
                while ContinuousClock.now < visibilityDeadline,
                      !NSApp.windows.contains(where: {
                          $0.identifier?.rawValue == BarlineWindowIdentifier.settings.rawValue && $0.isVisible
                      })
                {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                succeeded = succeeded && NSApp.windows.contains(where: {
                    $0.identifier?.rawValue == BarlineWindowIdentifier.settings.rawValue && $0.isVisible
                })
                let defaults = UserDefaults.standard
                defaults.set(succeeded, forKey: Self.reopenRecoverySucceededKey)
                defaults.set(
                    defaults.integer(forKey: Self.reopenRecoveryGenerationKey) + 1,
                    forKey: Self.reopenRecoveryGenerationKey
                )
                defaults.synchronize()
            }
        }
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
        // Delay makes this more reliable for some reason. Cancel the prior
        // delayed activation so a burst of reopen events cannot enqueue
        // unbounded main-actor work.
        settingsOpenTask?.cancel()
        settingsOpenTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard let self else {
                return
            }
            settingsOpenTask = nil
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
