//
//  BarlineWindow.swift
//  Barline
//

import SwiftUI

// MARK: - BarlineWindow

/// A custom scene representing one of Barline's windows.
struct BarlineWindow<Content: View>: Scene {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// The window's identifier.
    let id: BarlineWindowIdentifier

    /// The window's content view.
    let content: Content

    /// Creates a window with an identifier constant.
    ///
    /// - Parameters:
    ///   - id: A custom identifier constant.
    ///   - content: The content view to display in the window.
    init(id: BarlineWindowIdentifier, @ViewBuilder content: () -> Content) {
        self.id = id
        self.content = content()
    }

    var body: some Scene {
        windowScene.once {
            // SwiftUI waits to create the underlying NSWindow until the scene
            // is first presented. We may need a valid window reference before
            // that point, so we open the window and immediately dismiss it.
            //
            // - Note: Both actions are called during the same run loop cycle,
            //   so the window isn't actually opened.
            openWindow(id: id)
            dismissWindow(id: id)
        }
    }

    @ViewBuilder
    private var windowContentView: some View {
        content.onWindowChange { window in
            window?.collectionBehavior.insert(.moveToActiveSpace)
        }
    }

    private var windowScene: some Scene {
        if #available(macOS 15.0, *) {
            return windowSceneModern
        } else {
            return windowSceneLegacy
        }
    }

    @available(macOS 15.0, *)
    private var windowSceneModern: some Scene {
        Window(id.titleKey, id: id.rawValue) {
            windowContentView
        }
        .defaultLaunchBehavior(.suppressed)
    }

    private var windowSceneLegacy: some Scene {
        Window(id.titleKey, id: id.rawValue) {
            windowContentView.once {
                // On launch, SwiftUI tries to show the first scene provided
                // to the app. Override this behavior and dismiss the window
                // the first time it is shown.
                dismissWindow(id: id)
            }
        }
    }
}

// MARK: - BarlineWindowIdentifier

/// Custom identifier constants uses to create Barline's windows.
enum BarlineWindowIdentifier: String, Sendable, CustomStringConvertible {
    /// The identifier for Barline's main settings window.
    case settings = "SettingsWindow"

    /// The identifier for Barline's permissions window.
    case permissions = "PermissionsWindow"

    /// The non-localized title of the corresponding window.
    ///
    /// - Note: Use ``titleKey`` to get the localized title.
    var titleString: String {
        switch self {
        case .settings: "Barline"
        case .permissions: "Permissions"
        }
    }

    /// The localized title of the corresponding window.
    ///
    /// - Note: Use ``titleString`` to get the non-localized title.
    var titleKey: LocalizedStringKey {
        LocalizedStringKey(titleString)
    }

    /// A textual representation of the identifier.
    var description: String {
        rawValue
    }
}

// MARK: - OpenWindowAction

extension OpenWindowAction {
    /// Opens the corresponding window for the given identifier.
    ///
    /// - Parameter id: An identifier for one of Barline's windows.
    func callAsFunction(id: BarlineWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}

// MARK: - DismissWindowAction

extension DismissWindowAction {
    /// Dismisses the corresponding window for the given identifier.
    ///
    /// - Parameter id: An identifier for one of Barline's windows.
    func callAsFunction(id: BarlineWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}
