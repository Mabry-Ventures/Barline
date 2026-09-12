//
//  ApplicationRelocator.swift
//  Barline
//

import AppKit
import BarlineCore
import OSLog

/// Offers to move Barline into Applications before first use. macOS ties
/// Accessibility and Screen Recording grants to where an app runs, so this runs
/// before anything that could request either permission.
@MainActor
enum ApplicationRelocator {
    private static let logger = Logger(category: "ApplicationRelocator")

    /// Offers a move when Barline runs outside an Applications folder, then calls
    /// `continueLaunch` unless a relocated copy was launched and this process is
    /// terminating. When no offer applies, `continueLaunch` runs synchronously.
    static func offerIfNeeded(continueLaunch: @escaping @MainActor () -> Void) {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let location = ApplicationLocationPolicy.location(
            bundlePath: bundleURL.path,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        let offer = ApplicationLocationPolicy.offer(
            for: location,
            isEligible: isEligibleBuild,
            userDeclined: Defaults.bool(forKey: .applicationLocationOfferDeclined)
        )
        switch offer {
        case .none:
            continueLaunch()
        case .moveAutomatically:
            offerAutomaticMove(from: bundleURL, continueLaunch: continueLaunch)
        case .moveManually:
            offerManualMove(for: location, continueLaunch: continueLaunch)
        }
    }

    /// Only copies distributed to users are eligible. Development builds and
    /// locally built Release products, including the gate lanes that launch a
    /// Release build from build products, must never be interrupted.
    private static var isEligibleBuild: Bool {
        #if DEBUG
            false
        #else
            DistributionIdentity.isDeveloperIDSigned
        #endif
    }

    private static func offerAutomaticMove(
        from source: URL,
        continueLaunch: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Move Barline to your Applications folder?"
        alert.informativeText = """
        macOS ties Accessibility and Screen Recording permission to where an app \
        runs. Moving Barline now keeps permission you grant from being reset later.
        """
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"
        logger.info("Offering to move Barline into Applications")
        guard present(alert) == .alertFirstButtonReturn else {
            continueLaunch()
            return
        }

        let destination = moveDestination(for: source)
        if FileManager.default.fileExists(atPath: destination.path), !confirmReplacement() {
            continueLaunch()
            return
        }

        Task { @MainActor in
            do {
                // Copying a whole app bundle can take a while on a slow or nearly
                // full disk, so file work runs off the main actor and only AppKit
                // presentation and relaunch return to it.
                try await Task.detached(priority: .userInitiated) {
                    try copyReplacing(destination, with: source)
                }.value
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
                // The relocated copy is running. Moving the old copy to the Trash,
                // rather than deleting it, keeps the move recoverable.
                _ = await Task.detached(priority: .userInitiated) {
                    try? FileManager.default.trashItem(at: source, resultingItemURL: nil)
                }.value
                logger.info("Moved Barline into Applications and relaunched it")
                NSApp.terminate(nil)
            } catch {
                logger.error("Could not move Barline into Applications")
                showMoveFailure()
                continueLaunch()
            }
        }
    }

    private static func offerManualMove(
        for location: ApplicationLocationPolicy.Location,
        continueLaunch: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Move Barline to your Applications folder"
        if location == .mountedVolume {
            alert.informativeText = """
            Barline is running from its disk image. Quit Barline, drag it onto the \
            Applications shortcut in the disk image window, then open it from \
            Applications. macOS ties Accessibility and Screen Recording permission \
            to where an app runs.
            """
        } else {
            alert.informativeText = """
            macOS is running Barline from a temporary location because it was \
            opened where it was downloaded. Quit Barline, drag it into your \
            Applications folder, then open it from there. macOS ties Accessibility \
            and Screen Recording permission to where an app runs.
            """
        }
        alert.addButton(withTitle: "Quit and Show Applications")
        alert.addButton(withTitle: "Continue Without Moving")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"
        logger.info("Asking the user to move Barline into Applications")
        guard present(alert) == .alertFirstButtonReturn else {
            continueLaunch()
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        NSApp.terminate(nil)
    }

    /// Presents an offer and records "Don't ask again" only when the user
    /// declines. Choosing to move never suppresses a later offer.
    private static func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on, response != .alertFirstButtonReturn {
            Defaults.set(true, forKey: .applicationLocationOfferDeclined)
        }
        return response
    }

    private static func confirmReplacement() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace the Barline already in Applications?"
        alert.informativeText = "The copy in your Applications folder will be replaced with this one."
        // Replacing overwrites the installed copy, so it must take a deliberate
        // click. Return chooses Cancel instead of the destructive action.
        let replace = alert.addButton(withTitle: "Replace")
        replace.hasDestructiveAction = true
        replace.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func showMoveFailure() {
        let alert = NSAlert()
        alert.messageText = "Barline couldn’t move itself to Applications"
        alert.informativeText = """
        Drag Barline into your Applications folder in Finder, then open it from \
        there. Barline will keep running from its current location for now.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    /// System Applications when this account can write to it; otherwise the
    /// user's own Applications folder, which standard accounts can write and the
    /// location policy already treats as installed.
    private static func moveDestination(for source: URL) -> URL {
        let fileManager = FileManager.default
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let folder = fileManager.isWritableFile(atPath: systemApplications.path)
            ? systemApplications
            : fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        return folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
    }

    /// Copies to a hidden staging name first so a failed copy never leaves a
    /// partial app at the destination, then swaps it into place. Any failure,
    /// including a copy that stops partway, removes the staged bundle.
    private nonisolated static func copyReplacing(_ destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.copyItem(at: source, to: staged)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fileManager.moveItem(at: staged, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }
}
