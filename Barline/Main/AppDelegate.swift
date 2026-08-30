//
//  AppDelegate.swift
//  Barline
//

import BarlineCore
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let reopenRecoveryGenerationKey = "ReopenRecoveryGeneration"
    private static let reopenRecoveryFailureKey = "ReopenRecoveryFailure"
    private static let reopenRecoverySucceededKey = "ReopenRecoverySucceeded"
    private static let reopenProbeBaselineGenerationKey = "ReopenProbeBaselineGeneration"
    private static let notificationPrefix = Bundle.main.bundleIdentifier ?? "Barline"
    private static let reopenProbeHideSettingsNotification = Notification.Name(
        "\(notificationPrefix).reopen-probe.hide-settings"
    )
    private static let reopenProbePresentationNotification = Notification.Name(
        "\(notificationPrefix).reopen-probe.presentation"
    )
    /// The shared app state.
    let appState = AppState()

    /// Coalesces repeated requests to activate the settings window.
    private var settingsOpenTask: Task<Void, Never>?

    /// Prevents bursts of reopen events from starting overlapping XPC refreshes.
    private var reopenRecoveryTask: Task<Void, Never>?

    /// Preserves one completion acknowledgement for every reopen event received
    /// while the serialized compatibility recovery task is still draining.
    private var pendingReopenRecoveryCount = 0

    #if DEBUG
        private static let runtimeSmokeToggleNotification = Notification.Name(
            "\(notificationPrefix).runtime-smoke.toggle-shelf"
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

        if CommandLine.arguments.contains("--barline-reopen-probe") {
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(hideSettingsForReopenProbe),
                name: Self.reopenProbeHideSettingsNotification,
                object: nil
            )
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
        // Keep every reopen responsive even if a prior compatibility recovery
        // is still in flight. The opener coalesces bursts independently.
        openSettingsWindow()
        // A reopen is also a safe recovery opportunity for the compatibility
        // backend. This keeps the app process alive while replacing an
        // interrupted XPC helper before the user performs another action.
        pendingReopenRecoveryCount += 1
        if reopenRecoveryTask == nil {
            reopenRecoveryTask = Task { [weak self] in
                guard let self else {
                    return
                }
                defer { reopenRecoveryTask = nil }
                while pendingReopenRecoveryCount > 0 {
                    pendingReopenRecoveryCount -= 1
                    await completeReopenRecovery()
                }
            }
        }
        return true
    }

    private func completeReopenRecovery() async {
        var succeeded = true
        var failureDescription: String?
        await appState.waitForSetup()
        do {
            do {
                _ = try await appState.compatibilityCoordinator.refresh()
            } catch let error as MenuBarBackendError {
                switch error {
                case .interrupted, .invalidSnapshot(.nonMonotonicGeneration):
                    // A replacement XPC helper can either interrupt the
                    // in-flight request or start a new raw generation epoch.
                    // In both cases, replace the session and rebase it.
                    _ = try await appState.compatibilityCoordinator.recover()
                default:
                    throw error
                }
            }
            await appState.profileManager.reconcileActiveProfileAuthority()
        } catch {
            succeeded = false
            failureDescription = recoveryFailureCategory(for: error)
            Logger.default.error(
                "Compatibility refresh on reopen failed: \(failureDescription ?? "unknown", privacy: .public)"
            )
        }
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
        defaults.set(failureDescription, forKey: Self.reopenRecoveryFailureKey)
        defaults.set(
            defaults.integer(forKey: Self.reopenRecoveryGenerationKey) + 1,
            forKey: Self.reopenRecoveryGenerationKey
        )
        defaults.synchronize()
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
            guard CommandLine.arguments.contains("--barline-reopen-probe") else {
                return
            }
            let visibilityDeadline = ContinuousClock.now + .seconds(1)
            while ContinuousClock.now < visibilityDeadline,
                  !NSApp.windows.contains(where: {
                      $0.identifier?.rawValue == BarlineWindowIdentifier.settings.rawValue && $0.isVisible
                  })
            {
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard NSApp.windows.contains(where: {
                $0.identifier?.rawValue == BarlineWindowIdentifier.settings.rawValue && $0.isVisible
            }) else {
                return
            }
            DistributedNotificationCenter.default().postNotificationName(
                Self.reopenProbePresentationNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }

    /// Establishes a hidden-window baseline for the explicit local reopen probe.
    /// The launch argument keeps this test-only control unavailable in normal use.
    @objc private func hideSettingsForReopenProbe() {
        guard CommandLine.arguments.contains("--barline-reopen-probe") else {
            return
        }
        settingsOpenTask?.cancel()
        settingsOpenTask = nil
        for window in NSApp.windows where
            window.identifier?.rawValue == BarlineWindowIdentifier.settings.rawValue
        {
            window.orderOut(nil)
        }
        appState.deactivate(withPolicy: .accessory)
        let defaults = UserDefaults.standard
        defaults.set(
            defaults.integer(forKey: Self.reopenProbeBaselineGenerationKey) + 1,
            forKey: Self.reopenProbeBaselineGenerationKey
        )
        defaults.synchronize()
    }

    private func recoveryFailureCategory(for error: Error) -> String {
        guard let backendError = error as? MenuBarBackendError else {
            return "unexpected-error"
        }
        return switch backendError {
        case .unavailableCapability:
            "unavailable-capability"
        case .staleItem:
            "stale-item"
        case .unsafeMenuTracking:
            "unsafe-menu-tracking"
        case let .invalidSnapshot(reason):
            snapshotRejectionCategory(reason)
        case .interrupted:
            "interrupted"
        case .timedOut:
            "timed-out"
        case .operationFailed:
            "operation-failed"
        }
    }

    private func snapshotRejectionCategory(_ reason: SnapshotRejectionReason) -> String {
        switch reason {
        case .missingDisplayGeometry: "invalid-snapshot-missing-display-geometry"
        case .invalidActiveSpace: "invalid-snapshot-active-space"
        case .staleSnapshot: "invalid-snapshot-stale"
        case .futureDatedSnapshot: "invalid-snapshot-future-dated"
        case .unknownItemDisplay: "invalid-snapshot-unknown-item-display"
        case .displayIdentitySetMismatch: "invalid-snapshot-display-identity-set"
        case .duplicateDisplayIdentity: "invalid-snapshot-duplicate-display"
        case .malformedDisplayFingerprint: "invalid-snapshot-display-fingerprint"
        case .duplicateItemIdentity: "invalid-snapshot-duplicate-item"
        case .unstableItemIdentity: "invalid-snapshot-unstable-item"
        case .invalidItemGeometry: "invalid-snapshot-item-geometry"
        case .missingRequiredControlItem: "invalid-snapshot-missing-control"
        case .implausibleItemCountCollapse: "invalid-snapshot-item-collapse"
        case .implausibleSystemItemCollapse: "invalid-snapshot-system-item-collapse"
        case .emptySnapshot: "invalid-snapshot-empty"
        case .nonMonotonicGeneration: "invalid-snapshot-generation"
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
