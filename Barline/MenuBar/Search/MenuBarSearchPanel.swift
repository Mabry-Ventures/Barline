//
//  MenuBarSearchPanel.swift
//  Barline
//

import BarlineCore
import Combine
import OSLog
import SwiftUI

/// A panel that contains the menu bar search interface.
final class MenuBarSearchPanel: NSPanel {
    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Model for menu bar item search.
    private let model = MenuBarSearchModel()

    /// Monitor for mouse down events.
    private lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState,
            event.window !== self
        else {
            return event
        }
        if !appState.itemManager.lastMoveOperationOccurred(within: .seconds(1)) {
            close()
        }
        return event
    }

    /// Monitor for key down events.
    private lazy var keyDownMonitor = EventMonitor.universal(
        for: [.keyDown]
    ) { [weak self] event in
        if KeyCode(rawValue: Int(event.keyCode)) == .escape {
            self?.close()
            return nil
        }
        return event
    }

    /// The default screen to show the panel on.
    var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// Overridden to always be `true`.
    override var canBecomeKey: Bool {
        true
    }

    /// Creates a menu bar search panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        animationBehavior = .none
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
    }

    /// Performs the initial setup of the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        model.performSetup(with: self)
    }

    /// Configures the internal observers for the panel.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] effectiveAppearance in
                self?.appearance = effectiveAppearance
            }
            .store(in: &c)

        // Close the panel when the active space changes, or when the screen parameters change.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            self?.close()
        }
        .store(in: &c)

        cancellables = c
    }

    /// Shows the search panel on the given screen.
    func show(on screen: NSScreen? = nil) {
        guard let appState else {
            return
        }

        guard let screen = screen ?? defaultScreen else {
            Logger.default.error("Missing screen for search panel")
            return
        }

        // Important that we set the navigation state before updating the cache.
        appState.navigationState.isSearchPresented = true

        Task {
            await appState.imageCache.updateCache()

            let hostingView = MenuBarSearchHostingView(appState: appState, model: model, displayID: screen.displayID, panel: self)
            hostingView.setFrameSize(hostingView.intrinsicContentSize)
            setFrame(hostingView.frame, display: true)

            contentView = hostingView

            // Calculate the top left position.
            let topLeft = CGPoint(
                x: screen.frame.midX - frame.width / 2,
                y: screen.frame.midY + (frame.height / 2) + (screen.frame.height / 8)
            )

            cascadeTopLeft(from: topLeft)
            makeKeyAndOrderFront(nil)

            mouseDownMonitor.start()
            keyDownMonitor.start()
        }
    }

    /// Toggles the panel's visibility.
    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    /// Dismisses the search panel.
    override func close() {
        super.close()
        contentView = nil
        mouseDownMonitor.stop()
        keyDownMonitor.stop()
        appState?.navigationState.isSearchPresented = false
    }
}

private final class MenuBarSearchHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        appState: AppState,
        model: MenuBarSearchModel,
        displayID _: CGDirectDisplayID,
        panel: MenuBarSearchPanel
    ) {
        super.init(
            rootView: MenuBarSearchContentView { [weak panel] in panel?.close() }
                .environmentObject(appState)
                .environmentObject(appState.itemManager)
                .environmentObject(appState.imageCache)
                .environmentObject(appState.profileManager)
                .environmentObject(model)
                .erasedToAnyView()
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }
}

private struct MenuBarSearchContentView: View {
    private typealias ListItem = SectionedListItem<MenuBarSearchModel.ItemID>

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var model: MenuBarSearchModel
    @EnvironmentObject var profileManager: ProfileManager
    @FocusState private var searchFieldIsFocused: Bool

    let closePanel: () -> Void

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty || !profileManager.profiles.isEmpty
    }

    private var bottomBarPadding: CGFloat {
        if #available(macOS 26.0, *) {
            7
        } else {
            5
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            mainContent
            commandStatus
            bottomBar
        }
        .background {
            VisualEffectView(material: .sheet, blendingMode: .behindWindow)
                .opacity(0.5)
        }
        .frame(width: 600, height: 400)
        .fixedSize()
        .task {
            searchFieldIsFocused = true
        }
        .onChange(of: model.searchText, initial: true) {
            updateDisplayedItems()
            selectFirstDisplayedItem()
        }
        .onChange(of: itemManager.itemCache, initial: true) {
            updateDisplayedItems()
            if model.selection == nil {
                selectFirstDisplayedItem()
            }
        }
        .onChange(of: profileManager.profiles, initial: true) {
            updateDisplayedItems()
            if model.selection == nil {
                selectFirstDisplayedItem()
            }
        }
    }

    @ViewBuilder
    private var commandStatus: some View {
        switch model.commandInterpretationState {
        case .interpreting:
            HStack {
                ProgressView().controlSize(.small)
                Text("Interpreting on this Mac…")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .accessibilityIdentifier("search-command-interpreting")
        case let .validated(command), let .previewRequired(command):
            commandAction(
                for: command,
                disposition: SearchCommandExecutionPolicy().disposition(for: command)
            )
        case let .nonRunnable(command, reason):
            commandAction(for: command, disposition: .nonRunnable(reason))
        case .idle, .deterministicOnly, .unavailable, .fallback:
            EmptyView()
        }
    }

    private func commandAction(
        for command: ValidatedMenuBarCommand,
        disposition: SearchCommandExecutionDisposition
    ) -> some View {
        HStack {
            Label(
                commandActionSummary(command, disposition: disposition),
                systemImage: disposition == .executableImmediately ? "sparkles" : "exclamationmark.shield"
            )
            Spacer()
            switch disposition {
            case .executableImmediately:
                Button("Run") {
                    executeValidatedCommand(command, confirmationGranted: false)
                }
            case .explicitConfirmationRequired:
                Button("Confirm") {
                    executeValidatedCommand(command, confirmationGranted: true)
                }
            case let .nonRunnable(reason):
                if nonRunnableCommandCanBeEditedManually(reason) {
                    Button("Edit Manually") { openManualEditor(for: command) }
                } else {
                    Button("Dismiss") { model.resetCommandInterpretation() }
                }
            }
        }
        .padding(8)
        .accessibilityIdentifier("search-command-action")
    }

    private func commandActionSummary(
        _ command: ValidatedMenuBarCommand,
        disposition: SearchCommandExecutionDisposition
    ) -> String {
        let summary = commandSummary(command)
        guard case let .nonRunnable(reason) = disposition else { return summary }
        return switch reason {
        case .atomicBatchMutationUnavailable:
            "Cannot run this batch atomically. \(summary) manually in Layout Settings."
        case .missingArrangementDestination, .missingGroupDefinition:
            summary
        case .targetUnavailable:
            "Cannot run: the target is no longer available."
        case .targetIsOffScreen:
            "Cannot run: reveal this menu bar item before activating it."
        case .targetIsNotMovable:
            "Cannot run: this menu bar item cannot be moved."
        case .targetCannotBeHidden:
            "Cannot run: this menu bar item cannot be hidden."
        }
    }

    private func nonRunnableCommandCanBeEditedManually(
        _ reason: SearchCommandNonRunnableReason
    ) -> Bool {
        switch reason {
        case .atomicBatchMutationUnavailable, .missingArrangementDestination, .missingGroupDefinition:
            true
        case .targetUnavailable, .targetIsOffScreen, .targetIsNotMovable, .targetCannotBeHidden:
            false
        }
    }

    @ViewBuilder
    private var searchField: some View {
        let promptText = Text("Search menu bar items…")

        VStack(spacing: 0) {
            TextField(text: $model.searchText, prompt: promptText) {
                promptText
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .font(.system(size: 18))
            .padding(15)
            .focused($searchFieldIsFocused)

            Divider()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if hasItems {
            SectionedList(selection: $model.selection, items: $model.displayedItems)
                .contentPadding(8)
                .scrollContentBackground(.hidden)
        } else {
            VStack {
                Text("Loading menu bar items…")
                    .font(.title2)
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bottomBar: some View {
        HStack {
            SettingsButton {
                closePanel()
                itemManager.appState?.activate(withPolicy: .regular)
                itemManager.appState?.openWindow(.settings)
            }

            Spacer()

            if
                let selection = model.selection,
                let item = menuBarItem(for: selection)
            {
                ShowItemButton(item: item) {
                    performAction(for: item)
                }
            }
        }
        .padding(bottomBarPadding)
        .background(.thinMaterial)
        .buttonStyle(BottomBarButtonStyle())
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func selectFirstDisplayedItem() {
        model.selection = model.displayedItems.first { $0.isSelectable }?.id
    }

    private func updateDisplayedItems() {
        typealias SearchItem = (listItem: ListItem, document: SearchDocument?)

        var searchItems = [SearchItem]()

        if !profileManager.profiles.isEmpty {
            let headerItem = ListItem.header(id: .profileHeader) {
                Text("Profiles")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            searchItems.append(SearchItem(headerItem, nil))

            for profile in profileManager.profiles.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                let listItem = ListItem.item(id: .profile(profile.id)) {
                    performAction(for: profile)
                } content: {
                    Label(profile.name, systemImage: profile.symbol ?? "rectangle.3.group")
                        .padding(8)
                }
                let document = SearchDocument(
                    id: SearchDocumentID("profile \(profile.id.uuidString)"),
                    kind: .profile,
                    entity: .profile(ProfileID(profile.id.uuidString)),
                    title: profile.name,
                    groups: profile.searchableGroupNames,
                    synonyms: ["profile", "layout"],
                    keywords: ["switch", "activate"],
                    lastUsedAt: profile.id == profileManager.activeProfileID
                        ? profileManager.activeProfileActivatedAt
                        : nil
                )
                searchItems.append(SearchItem(listItem, document))
            }
        }

        for name in MenuBarSection.Name.allCases {
            if
                let appState = itemManager.appState,
                let section = appState.menuBarManager.section(withName: name),
                !section.isEnabled
            {
                continue
            }

            let headerItem = ListItem.header(id: .header(name)) {
                Text(name.displayString)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            searchItems.append(SearchItem(headerItem, nil))

            for item in itemManager.itemCache.managedItems(for: name).reversed() {
                let listItem = ListItem.item(id: .item(item.tag)) {
                    performAction(for: item)
                } content: {
                    MenuBarSearchItemView(item: item)
                }
                let memberships = profileManager.profiles
                    .filter { $0.searchableItemIDs.contains(item.stableID) }
                    .map(\.name)
                let document = SearchDocument(
                    id: item.stableID.searchDocumentID,
                    kind: .menuBarItem,
                    entity: .menuBarItem(item.stableID),
                    title: item.displayName,
                    bundleIdentifier: item.stableID.bundleIdentifier,
                    aliases: [item.title, item.stableID.alias].compactMap(\.self),
                    groups: profileManager.profiles.flatMap { profile in
                        profile.searchableGroupNames(containing: item.stableID)
                    },
                    profileMemberships: memberships,
                    keywords: ["menu bar", "status item"]
                )
                searchItems.append(SearchItem(listItem, document))
            }
        }

        let documents = searchItems.compactMap(\.document)

        if model.searchText.isEmpty {
            model.displayedItems = searchItems.map(\.listItem)
            model.synchronizeSpotlightIfNeeded(with: documents)
            model.resetCommandInterpretation()
        } else {
            let itemsByDocumentID = Dictionary(uniqueKeysWithValues: searchItems.compactMap { searchItem in
                searchItem.document.map { ($0.id, searchItem.listItem) }
            })
            let results = model.rankedResults(for: model.searchText, documents: documents)
            model.displayedItems = results
                .map(\.document.id)
                .compactMap { itemsByDocumentID[$0] }
            model.considerCommandInterpretation(
                query: model.searchText,
                documents: documents,
                deterministicResults: results,
                coordinator: appState.compatibilityCoordinator,
                availableProfileIDs: Set(
                    profileManager.profiles.map { ProfileID($0.id.uuidString) }
                )
            )
        }
    }

    private func menuBarItem(for selection: MenuBarSearchModel.ItemID) -> MenuBarItem? {
        switch selection {
        case let .item(tag):
            itemManager.itemCache.managedItems.first(matching: tag)
        case .header, .profileHeader, .profile:
            nil
        }
    }

    private func performAction(for profile: BarlineProfile) {
        guard requireAccessibilityForAction() else { return }
        closePanel()
        Task {
            await profileManager.activate(profile)
        }
    }

    private func performAction(for item: MenuBarItem) {
        guard requireAccessibilityForAction() else { return }
        closePanel()
        Task {
            try await Task.sleep(for: .milliseconds(25))
            if item.isOnScreen {
                try await itemManager.click(item: item, with: .left)
            } else {
                await itemManager.temporarilyShow(item: item, clickingWith: .left)
            }
        }
    }

    private func requireAccessibilityForAction() -> Bool {
        guard appState.permissions.accessibility.hasPermission else {
            closePanel()
            appState.navigationState.settingsNavigationIdentifier = .advanced
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
            return false
        }
        return true
    }

    private func commandSummary(_ command: ValidatedMenuBarCommand) -> String {
        let count = command.targetItemIDs.count
        let itemNames = command.targetItemIDs.compactMap { itemID in
            itemManager.itemCache.managedItems.first(where: { $0.stableID == itemID })?.displayName
        }
        let itemDescription = itemNames.isEmpty
            ? "\(count) item\(count == 1 ? "" : "s")"
            : itemNames.prefix(3).joined(separator: ", ")
        return switch command.operation {
        case .activateProfile: "Switch to \(profileName(for: command) ?? "the suggested profile")"
        case .replaceWithProfile: "Replace the layout with \(profileName(for: command) ?? "the suggested profile")"
        case .reveal: "Reveal \(itemDescription)"
        case .activate: "Open \(itemDescription)"
        case .show: "Show \(itemDescription)"
        case .hide: "Hide \(itemDescription)"
        case .rearrange: "Cannot run: choose positions for \(itemDescription) in Layout Settings"
        case .group: "Cannot run: name and configure the group in Layout Settings"
        }
    }

    private func profileName(for command: ValidatedMenuBarCommand) -> String? {
        guard let profileID = command.targetProfileID else { return nil }
        return profileManager.profiles.first {
            ProfileID($0.id.uuidString) == profileID
        }?.name
    }

    private func executeValidatedCommand(
        _ command: ValidatedMenuBarCommand,
        confirmationGranted: Bool
    ) {
        let disposition = SearchCommandExecutionPolicy().disposition(for: command)
        switch disposition {
        case .executableImmediately:
            break
        case .explicitConfirmationRequired where confirmationGranted:
            break
        case .explicitConfirmationRequired, .nonRunnable:
            return
        }

        Task {
            do {
                let snapshot = try await appState.compatibilityCoordinator.refreshAuthority(
                    expectedGeneration: command.authorityGeneration
                )
                if case let .nonRunnable(reason) = SearchCommandExecutionPolicy().disposition(
                    for: command,
                    in: snapshot
                ) {
                    model.markCommandNonRunnable(command, reason: reason)
                    return
                }
                guard requireAccessibilityForAction() else { return }
                switch command.operation {
                case .reveal:
                    guard let itemID = command.targetItemIDs.first else { return }
                    let priorProfileID = await appState.compatibilityCoordinator.activeProfileID
                    _ = try await appState.compatibilityCoordinator.perform(
                        .reveal(itemID),
                        expectedGeneration: snapshot.generation
                    )
                    await profileManager.clearActiveProfileAuthority(ifMatches: priorProfileID)
                case .activate:
                    guard let itemID = command.targetItemIDs.first else { return }
                    _ = try await appState.compatibilityCoordinator.perform(
                        .activate(itemID, .left),
                        expectedGeneration: snapshot.generation
                    )
                case .show, .hide:
                    guard
                        command.targetItemIDs.count == 1,
                        let itemID = command.targetItemIDs.first,
                        let item = snapshot.items.first(where: { $0.id == itemID })
                    else {
                        return
                    }
                    let targetSection: BarlineCore.MenuBarSection = command.operation == .show
                        ? .visible
                        : .hidden
                    guard item.section != targetSection else {
                        closePanel()
                        return
                    }
                    let targetIndex = MenuBarMovePlanner().destinationIndex(
                        in: snapshot,
                        section: targetSection,
                        preferredDisplayID: item.displayID
                    )
                    let priorProfileID = await appState.compatibilityCoordinator.activeProfileID
                    _ = try await appState.compatibilityCoordinator.perform(
                        .move(
                            MenuBarMoveOperation(
                                itemID: itemID,
                                section: targetSection,
                                index: targetIndex,
                                destinationDisplayID: item.displayID
                            )
                        ),
                        expectedGeneration: snapshot.generation
                    )
                    await profileManager.clearActiveProfileAuthority(ifMatches: priorProfileID)
                case .activateProfile, .replaceWithProfile:
                    guard let profileID = command.targetProfileID,
                          let profile = profileManager.profiles.first(where: {
                              ProfileID($0.id.uuidString) == profileID
                          })
                    else { return }
                    guard await profileManager.activate(
                        profile,
                        expectedGeneration: snapshot.generation
                    ) else {
                        model.resetCommandInterpretation()
                        return
                    }
                case .rearrange, .group:
                    return
                }
                closePanel()
            } catch {
                model.resetCommandInterpretation()
            }
        }
    }

    private func openManualEditor(for command: ValidatedMenuBarCommand) {
        closePanel()
        if command.operation == .group {
            appState.navigationState.settingsNavigationIdentifier = .profiles
            appState.navigationState.requestedProfileEditorID = groupEditingProfile(for: command)?.id
        } else {
            appState.navigationState.settingsNavigationIdentifier = command.targetProfileID == nil
                ? .menuBarLayout
                : .profiles
        }
        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
    }

    private func groupEditingProfile(for command: ValidatedMenuBarCommand) -> BarlineProfile? {
        let targetItems = Set(command.targetItemIDs)
        let candidates = profileManager.profiles.filter {
            targetItems.isSubset(of: Set($0.layout.allItemIDs))
        }
        return candidates.first(where: { $0.id == profileManager.activeProfileID })
            ?? candidates.first
            ?? profileManager.profiles.first(where: { $0.id == profileManager.activeProfileID })
            ?? profileManager.profiles.first
    }
}

private struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(.barlineControlStroke)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(2)
        }
    }
}

private struct ShowItemButton: View {
    let item: MenuBarItem
    let action: () -> Void

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .circular)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text("\(item.isOnScreen ? "Click" : "Show") Item")
                    .padding(.leading, 5)

                Image(systemName: "return")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(.secondary)
                    .fontWeight(.bold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background {
                        backgroundShape
                            .fill(.regularMaterial)
                            .brightness(0.25)
                            .opacity(0.5)
                    }
            }
        }
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 22)
            .frame(minWidth: 22)
            .padding(3)
            .background {
                borderShape
                    .fill(.regularMaterial)
                    .brightness(0.25)
                    .opacity(configuration.isPressed ? 0.5 : isHovering ? 0.25 : 0)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

@MainActor
private let controlCenterIcon: NSImage? = {
    guard let app = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
        .first
    else {
        return nil
    }
    return app.icon
}()

private struct MenuBarSearchItemView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @EnvironmentObject var model: MenuBarSearchModel

    let item: MenuBarItem

    private var itemImage: NSImage {
        guard
            let cached = imageCache.images[item.tag],
            let trimmed = cached.cgImage.trimmingTransparency(around: [.minXEdge, .maxXEdge])
        else {
            return NSImage()
        }
        let size = CGSize(
            width: CGFloat(trimmed.width) / cached.scale,
            height: CGFloat(trimmed.height) / cached.scale
        )
        return NSImage(cgImage: trimmed, size: size)
    }

    private var appIcon: NSImage? {
        guard let app = item.sourceApplication else {
            return nil
        }
        switch item.tag.namespace {
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            return controlCenterIcon
        default:
            return app.icon
        }
    }

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    private var dimension: CGFloat {
        if #available(macOS 26.0, *) {
            26
        } else {
            24
        }
    }

    private var padding: CGFloat {
        if #available(macOS 26.0, *) {
            6
        } else {
            8
        }
    }

    var body: some View {
        HStack {
            Label {
                labelText
            } icon: {
                labelIcon
            }
            Spacer()
            itemView
        }
        .padding(padding)
    }

    private var labelText: some View {
        Text(item.displayName)
    }

    @ViewBuilder
    private var labelIcon: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: dimension, height: dimension)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.gradient)
                .strokeBorder(Color.primary.gradient.quaternary)
                .overlay {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .padding(3)
                        .shadow(radius: 2)
                }
                .padding(2.5)
                .shadow(color: .black.opacity(0.1), radius: 2)
                .frame(width: dimension, height: dimension)
        }
    }

    private var itemView: some View {
        Image(nsImage: itemImage)
            .frame(
                width: item.bounds.width,
                height: dimension
            )
            .menuBarItemContainer(
                appState: appState,
                colorInfo: model.averageColorInfo
            )
            .clipShape(backgroundShape)
            .overlay {
                backgroundShape
                    .strokeBorder(.quaternary)
            }
    }
}
