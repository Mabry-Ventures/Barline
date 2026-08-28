//
//  BarlineShelf.swift
//  Barline
//

import BarlineCore
import Combine
import OSLog
import SwiftUI

// MARK: - BarlineShelfPanel

final class BarlineShelfPanel: NSPanel {
    /// A token that identifies one request to present the Barline Bar.
    struct PresentationRequest {
        fileprivate let section: MenuBarSection.Name
        fileprivate let generation: UInt
        fileprivate let start: ContinuousClock.Instant
    }

    /// The shared app state.
    private weak var appState: AppState?

    /// Manager for the Barline Bar's color.
    private let colorManager = BarlineShelfColorManager()

    /// The currently displayed section.
    private(set) var currentSection: MenuBarSection.Name?

    /// Identifies the most recent show/close request.
    ///
    /// Cache updates in `show` suspend. Without an ownership token, an older
    /// show request can finish after `close` and reopen the panel.
    private var presentationGeneration: UInt = 0

    /// The cache refresh associated with the active presentation.
    private var cacheRefreshTask: Task<Void, Never>?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Creates a new Barline Bar panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        title = "Barline Bar"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        allowsToolTipsWhenApplicationIsInactive = true
        isFloatingPanel = true
        animationBehavior = .none
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 1
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
    }

    /// Sets up the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        colorManager.performSetup(with: self)
    }

    /// Configures the internal observers.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Hide the panel when the active space or screen parameters change.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            self?.hide()
        }
        .store(in: &c)

        // Update the panel's origin whenever its size changes.
        publisher(for: \.frame).map(\.size)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let screen else {
                    return
                }
                updateOrigin(for: screen)
            }
            .store(in: &c)

        if let controlItem = appState?.menuBarManager.controlItem(withName: .hidden) {
            // Use the hidden control item's frame to determine if the menu bar
            // is hidden. Hide the panel if so.
            controlItem.$frame
                .combineLatest(controlItem.$screen)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] frame, screen in
                    guard let self else {
                        return
                    }

                    // Missing geometry is common while AppKit rebuilds screens
                    // after wake. Only hide when the available geometry proves
                    // that the control item is vertically offscreen.
                    if MenuBarRecoveryPolicy.shouldHidePanel(
                        controlItemFrame: frame,
                        screenFrame: screen?.frame
                    ) {
                        hide()
                    }
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Updates the panel's frame origin for display on the given screen.
    private func updateOrigin(for screen: NSScreen) {
        guard let appState else {
            return
        }

        func getOrigin(for barlineShelfLocation: BarlineShelfLocation) -> CGPoint {
            let menuBarHeight = screen.getMenuBarHeight() ?? 0
            let originY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height

            var originForRightOfScreen: CGPoint {
                CGPoint(x: screen.frame.maxX - frame.width, y: originY)
            }

            switch barlineShelfLocation {
            case .dynamic:
                if appState.hidEventManager.isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) {
                    return getOrigin(for: .mousePointer)
                }
                return getOrigin(for: .barlineIcon)
            case .mousePointer:
                guard let location = MouseHelpers.locationAppKit else {
                    return getOrigin(for: .barlineIcon)
                }

                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard lowerBound <= upperBound else {
                    return originForRightOfScreen
                }

                return CGPoint(x: (location.x - frame.width / 2).clamped(to: lowerBound ... upperBound), y: originY)
            case .barlineIcon:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard
                    lowerBound <= upperBound,
                    let controlItem = appState.itemManager.itemCache.managedItems.first(matching: .visibleControlItem)
                else {
                    return originForRightOfScreen
                }
                let itemBounds = controlItem.bounds

                return CGPoint(x: (itemBounds.midX - frame.width / 2).clamped(to: lowerBound ... upperBound), y: originY)
            }
        }

        setFrameOrigin(getOrigin(for: appState.settings.general.barlineShelfLocation))
    }

    /// Synchronously claims ownership of the next panel presentation.
    ///
    /// This must happen before scheduling the asynchronous cache work so a
    /// subsequent `close` can invalidate the request even if its task has not
    /// started yet.
    func beginPresentation(for section: MenuBarSection.Name) -> PresentationRequest? {
        guard let appState else {
            return nil
        }

        cacheRefreshTask?.cancel()
        cacheRefreshTask = nil
        presentationGeneration &+= 1
        let request = PresentationRequest(
            section: section,
            generation: presentationGeneration,
            start: .now
        )

        // IMPORTANT: We must set the navigation state and current section
        // before updating the caches.
        appState.navigationState.isBarlineShelfPresented = true
        currentSection = section

        return request
    }

    /// Shows the panel on the given screen for a previously claimed
    /// presentation request.
    @discardableResult
    func show(_ request: PresentationRequest, on screen: NSScreen) async -> Bool {
        guard
            let appState,
            request.generation == presentationGeneration,
            currentSection == request.section,
            appState.navigationState.isBarlineShelfPresented
        else {
            return false
        }

        // Present the last known-good cache immediately. Refreshing menu bar
        // items and capturing their images can take hundreds of milliseconds,
        // especially while Control Center is relaying out status items. That
        // work must not block the first visible frame after a user click.
        let needsLoadingState = appState.itemManager.itemCache.managedItems.isEmpty ||
            appState.imageCache.cacheFailed(for: request.section)
        let hostingView: BarlineShelfHostingView
        if
            let reusableView = contentView as? BarlineShelfHostingView,
            reusableView.matches(screen: screen, section: request.section)
        {
            reusableView.setPreparing(needsLoadingState)
            hostingView = reusableView
        } else {
            // A loading-only first render avoids constructing every item image
            // before AppKit can order the window. The cached content replaces
            // it immediately after the first frame commits.
            hostingView = BarlineShelfHostingView(
                appState: appState,
                colorManager: colorManager,
                screen: screen,
                section: request.section,
                isPreparing: true
            )
            contentView = hostingView
        }

        updateOrigin(for: screen)

        // Color manager must be updated after updating the panel's origin,
        // but before it is shown.
        //
        // Color manager handles frame changes automatically, but does so on
        // the main queue, so we need to update manually once before showing
        // the panel to prevent the color from flashing.
        colorManager.updateAllProperties(with: frame, screen: screen)

        orderFrontRegardless()

        let firstFrameLatency = request.start.duration(to: .now)
        Logger.default.debug(
            "Ordered BarlineShelfPanel front after \(String(describing: firstFrameLatency), privacy: .public)"
        )

        // Give AppKit and WindowServer a short commit runway before starting
        // cache work on the main actor. Merely ordering the panel is not
        // enough: entering item discovery within one display frame can still
        // postpone the first visible frame until that work suspends.
        cacheRefreshTask = Task { [weak self, weak hostingView] in
            guard let self, let hostingView else {
                return
            }
            await refreshCache(
                for: request,
                hostingView: hostingView,
                needsLoadingState: needsLoadingState
            )
        }

        return true
    }

    /// Refreshes the caches after allowing the first panel frame to commit.
    private func refreshCache(
        for request: PresentationRequest,
        hostingView: BarlineShelfHostingView,
        needsLoadingState: Bool
    ) async {
        do {
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            return
        }

        guard
            let appState,
            !Task.isCancelled,
            request.generation == presentationGeneration,
            currentSection == request.section,
            appState.navigationState.isBarlineShelfPresented
        else {
            return
        }

        if !needsLoadingState {
            hostingView.finishPreparing()
        }

        let cacheTask = Task(timeout: .seconds(1)) {
            await appState.itemManager.cacheItemsIfNeeded()
            await appState.imageCache.updateCache()
        }

        do {
            try await withTaskCancellationHandler {
                try await cacheTask.value
            } onCancel: {
                cacheTask.cancel()
            }
        } catch is CancellationError {
            return
        } catch {
            Logger.default.error("Cache update failed when showing BarlineShelfPanel - \(error)")
        }

        guard
            !Task.isCancelled,
            request.generation == presentationGeneration,
            currentSection == request.section,
            appState.navigationState.isBarlineShelfPresented
        else {
            return
        }

        if needsLoadingState {
            hostingView.finishPreparing()
        }

        cacheRefreshTask = nil
    }

    /// Hides the panel.
    func hide() {
        if
            let name = currentSection,
            let section = appState?.menuBarManager.section(withName: name)
        {
            section.hide()
        }
        close()
    }

    override func close() {
        cacheRefreshTask?.cancel()
        cacheRefreshTask = nil
        presentationGeneration &+= 1
        super.close()
        currentSection = nil
        appState?.navigationState.isBarlineShelfPresented = false
    }
}

// MARK: - BarlineShelfHostingView

private final class BarlineShelfHostingView: NSHostingView<BarlineShelfContentView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    private let displayID: CGDirectDisplayID
    private let section: MenuBarSection.Name

    init(
        appState: AppState,
        colorManager: BarlineShelfColorManager,
        screen: NSScreen,
        section: MenuBarSection.Name,
        isPreparing: Bool
    ) {
        displayID = screen.displayID
        self.section = section
        let rootView = BarlineShelfContentView(
            appState: appState,
            colorManager: colorManager,
            itemManager: appState.itemManager,
            imageCache: appState.imageCache,
            menuBarManager: appState.menuBarManager,
            screen: screen,
            section: section,
            isPreparing: isPreparing
        )
        super.init(rootView: rootView)
    }

    /// Returns whether the view can be reused for a new presentation.
    func matches(screen: NSScreen, section: MenuBarSection.Name) -> Bool {
        displayID == screen.displayID && self.section == section
    }

    /// Updates the transient loading state without replacing the hosting view.
    func setPreparing(_ isPreparing: Bool) {
        guard rootView.isPreparing != isPreparing else {
            return
        }
        var updatedRootView = rootView
        updatedRootView.isPreparing = isPreparing
        rootView = updatedRootView
    }

    /// Replaces the transient loading state after the first cache refresh.
    func finishPreparing() {
        setPreparing(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: BarlineShelfContentView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}

// MARK: - BarlineShelfContentView

private struct BarlineShelfContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var colorManager: BarlineShelfColorManager
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var imageCache: MenuBarItemImageCache
    @ObservedObject var menuBarManager: MenuBarManager
    @State private var frame = CGRect.zero
    @State private var scrollIndicatorsFlashTrigger = 0

    let screen: NSScreen
    let section: MenuBarSection.Name
    var isPreparing: Bool

    private var items: [MenuBarItem] {
        itemManager.itemsForBarlineShelf(in: section, on: screen)
    }

    private var presentation: ResolvedProfilePresentation? {
        guard let presentation = appState.profileManager.activePresentation else { return nil }
        guard presentation.destinationDisplayID == nil
            || presentation.destinationDisplayID == stableDisplayID
        else {
            return nil
        }
        return presentation
    }

    private var presentationElements: [ProfilePresentationElement] {
        ProfilePresentationProjector().elements(
            presentation: presentation,
            section: coreSection,
            orderedItemIDs: items.map(\.stableID)
        )
    }

    private var coreSection: BarlineCore.MenuBarSection {
        switch section {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    private var stableDisplayID: MenuBarDisplayID {
        let directDisplayID = screen.displayID
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(directDisplayID) else {
            return MenuBarDisplayID("display-\(directDisplayID)")
        }
        return MenuBarDisplayID(
            CFUUIDCreateString(nil, unmanagedUUID.takeRetainedValue()) as String
        )
    }

    private var configuration: MenuBarAppearanceConfigurationV2 {
        appState.appearanceManager.configuration
    }

    private var horizontalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return 3
        }
        return configuration.hasRoundedShape ? 7 : 5
    }

    private var verticalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return screen.hasNotch && configuration.hasRoundedShape ? 2 : 0
        }
        return screen.hasNotch ? 0 : 2
    }

    private var contentHeight: CGFloat? {
        guard let menuBarHeight = screen.getMenuBarHeight() else {
            return nil
        }
        if configuration.shapeKind != .noShape, configuration.isInset, screen.hasNotch {
            return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    private var clipShape: some InsettableShape {
        if configuration.hasRoundedShape {
            RoundedRectangle(cornerRadius: frame.height / 2, style: .circular)
        } else if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: frame.height / 4, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: frame.height / 5, style: .continuous)
        }
    }

    private var shadowOpacity: CGFloat {
        configuration.current.hasShadow ? 0.5 : 0.33
    }

    private var cachedContentWidth: CGFloat {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.stableID, $0) })
        return presentationElements.reduce(into: 0) { width, element in
            switch element {
            case let .item(itemID):
                if let item = itemByID[itemID] {
                    width += imageCache.images[item.tag]?.scaledSize.width ?? 0
                }
            case let .spacer(_, spacerWidth):
                width += spacerWidth
            case let .groupMarker(_, name, _):
                width += min(CGFloat(name.count * 6 + 14), 120)
            }
        }
    }

    var body: some View {
        ZStack {
            content
                .frame(height: contentHeight)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .menuBarItemContainer(appState: appState, colorInfo: colorManager.colorInfo)
                .foregroundStyle(colorManager.colorInfo?.color.brightness ?? 0 > 0.67 ? .black : .white)
                .clipShape(clipShape)
                .shadow(color: .black.opacity(shadowOpacity), radius: 2.5)

            if configuration.current.hasBorder {
                clipShape
                    .inset(by: configuration.current.borderWidth / 2)
                    .stroke(lineWidth: configuration.current.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.current.borderColor))
            }
        }
        .padding(5)
        .frame(maxWidth: screen.frame.width)
        .fixedSize()
        .onFrameChange(update: $frame)
    }

    @ViewBuilder
    private var content: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            HStack {
                Text("The Barline Bar requires screen recording permissions.")

                Button {
                    menuBarManager.section(withName: section)?.hide()
                    appState.navigationState.settingsNavigationIdentifier = .advanced
                    appState.activate(withPolicy: .regular)
                    appState.openWindow(.settings)
                } label: {
                    Text("Open Barline Settings")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            }
            .padding(.horizontal, 10)
        } else if menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            Text("Barline cannot display menu bar items for automatically hidden menu bars")
                .padding(.horizontal, 10)
        } else if isPreparing || itemManager.itemCache.managedItems.isEmpty {
            HStack {
                Text("Loading menu bar items…")
                ProgressView()
                    .controlSize(.small)
            }
            .frame(minWidth: cachedContentWidth)
            .padding(.horizontal, 10)
        } else if imageCache.cacheFailed(for: section) {
            Text("Unable to display menu bar items")
                .padding(.horizontal, 10)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(presentationElements) { element in
                        switch element {
                        case let .item(itemID):
                            if let item = items.first(where: { $0.stableID == itemID }) {
                                BarlineShelfItemView(
                                    imageCache: imageCache,
                                    itemManager: itemManager,
                                    menuBarManager: menuBarManager,
                                    item: item,
                                    section: section
                                )
                            }
                        case let .spacer(_, width):
                            Color.clear
                                .frame(width: width)
                                .accessibilityHidden(true)
                        case let .groupMarker(_, name, symbol):
                            HStack(spacing: 2) {
                                if let symbol, !symbol.isEmpty {
                                    Image(systemName: symbol)
                                }
                                Text(name)
                                    .lineLimit(1)
                            }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.16), in: Capsule())
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Group: \(name)")
                        }
                    }
                }
            }
            .environment(\.isScrollEnabled, frame.width == screen.frame.width)
            .defaultScrollAnchor(.trailing)
            .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
            .task {
                scrollIndicatorsFlashTrigger += 1
            }
        }
    }
}

// MARK: - BarlineShelfItemView

private struct BarlineShelfItemView: View {
    @ObservedObject var imageCache: MenuBarItemImageCache
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var menuBarManager: MenuBarManager

    let item: MenuBarItem
    let section: MenuBarSection.Name

    private var leftClickAction: () -> Void {
        { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            menuBarManager.section(withName: section)?.hide()
            Task {
                try await Task.sleep(for: .milliseconds(25))
                if item.isOnScreen {
                    try await itemManager.click(item: item, with: .left)
                } else {
                    await itemManager.temporarilyShow(item: item, clickingWith: .left)
                }
            }
        }
    }

    private var rightClickAction: () -> Void {
        { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            menuBarManager.section(withName: section)?.hide()
            Task {
                try await Task.sleep(for: .milliseconds(25))
                if item.isOnScreen {
                    try await itemManager.click(item: item, with: .right)
                } else {
                    await itemManager.temporarilyShow(item: item, clickingWith: .right)
                }
            }
        }
    }

    private var image: NSImage? {
        guard let cachedImage = imageCache.images[item.tag] else {
            return nil
        }
        return cachedImage.nsImage
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .contentShape(Rectangle())
                .overlay {
                    BarlineShelfItemClickView(
                        item: item,
                        leftClickAction: leftClickAction,
                        rightClickAction: rightClickAction
                    )
                }
                .accessibilityLabel(item.displayName)
                .accessibilityAction(named: "left click", leftClickAction)
                .accessibilityAction(named: "right click", rightClickAction)
        }
    }
}

// MARK: - BarlineShelfItemClickView

private struct BarlineShelfItemClickView: NSViewRepresentable {
    private final class Represented: NSView {
        let item: MenuBarItem

        let leftClickAction: () -> Void
        let rightClickAction: () -> Void

        private var lastLeftMouseDownDate = Date.now
        private var lastRightMouseDownDate = Date.now

        private var lastLeftMouseDownLocation = CGPoint.zero
        private var lastRightMouseDownLocation = CGPoint.zero

        init(
            item: MenuBarItem,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void
        ) {
            self.item = item
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            super.init(frame: .zero)
            toolTip = item.displayName
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = NSEvent.mouseLocation
        }

        override func rightMouseDown(with event: NSEvent) {
            super.rightMouseDown(with: event)
            lastRightMouseDownDate = .now
            lastRightMouseDownLocation = NSEvent.mouseLocation
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
                lastLeftMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            leftClickAction()
        }

        override func rightMouseUp(with event: NSEvent) {
            super.rightMouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
                lastRightMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            rightClickAction()
        }
    }

    let item: MenuBarItem

    let leftClickAction: () -> Void
    let rightClickAction: () -> Void

    func makeNSView(context _: Context) -> NSView {
        Represented(
            item: item,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction
        )
    }

    func updateNSView(_: NSView, context _: Context) {}
}
