//
//  MenuBarItemManager.swift
//  Barline
//

import BarlineCore
import Cocoa
import Combine
import OSLog

/// Manager for menu bar items.
@MainActor
final class MenuBarItemManager: ObservableObject {
    /// The current cache of menu bar items.
    @Published private(set) var itemCache = ItemCache(displayID: nil)

    /// Logger for the menu bar item manager.
    private nonisolated let logger = Logger.menuBarItemManager

    /// Semaphore to prevent overlapping event operations.
    private nonisolated let eventSemaphore = AsyncSemaphore(value: 1)

    /// Actor for managing menu bar item cache operations.
    private let cacheActor = CacheActor()

    /// Monotonically increasing identifier for cache requests.
    private var cacheRequestSequence: UInt64 = 0

    /// Contexts for temporarily shown menu bar items.
    private var temporarilyShownItemContexts = [TemporarilyShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    private var rehideTimer: Timer?

    /// Timestamp of the most recent menu bar item move operation.
    private var lastMoveOperationTimestamp: ContinuousClock.Instant?

    /// Cached timeouts for move operations.
    private var moveOperationTimeouts = [MenuBarItemTag: Duration]()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Sets up the manager.
    func performSetup(with appState: AppState) async {
        self.appState = appState
        await cacheItemsRegardless()
        configureCancellables(with: appState)
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables(with appState: AppState) {
        var c = Set<AnyCancellable>()

        NSWorkspace.shared.publisher(for: \.runningApplications)
            .discardMerge(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.didWakeNotification
                )
            )
            .discardMerge(
                NotificationCenter.default.publisher(
                    for: NSApplication.didChangeScreenParametersNotification
                )
            )
            .delay(for: 0.25, scheduler: DispatchQueue.main)
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else {
                    return
                }
                Task {
                    await self.cacheItemsIfNeeded()
                }
            }
            .store(in: &c)

        appState.navigationState.$settingsNavigationIdentifier
            .sink { [weak self] identifier in
                guard let self, identifier == .menuBarLayout else {
                    return
                }
                Task {
                    await self.cacheItemsRegardless()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether the most recent
    /// menu bar item move operation occurred within the given duration.
    func lastMoveOperationOccurred(within duration: Duration) -> Bool {
        guard let timestamp = lastMoveOperationTimestamp else {
            return false
        }
        return timestamp.duration(to: .now) <= duration
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// An actor that manages menu bar item cache operations.
    private final actor CacheActor {
        /// Stored task for the current cache operation.
        private var cacheTask: Task<Void, Never>?

        /// Identifier of the newest cache request accepted by this actor.
        private var currentRequestID: UInt64 = 0

        /// A list of the menu bar item window identifiers at the time
        /// of the previous cache.
        private(set) var cachedItemIDs = [MenuBarItemID]()

        /// Runs the given async closure as a task and waits for it to
        /// complete before returning.
        ///
        /// If a task from a previous call to this method is currently
        /// running, that task is cancelled and replaced.
        func runCacheTask(
            requestID: UInt64,
            operation: @escaping @MainActor @Sendable (UInt64) async -> Void
        ) async {
            // MainActor callers assign increasing IDs. Reject an older request
            // if actor scheduling ever delivers it after a newer one.
            guard requestID > currentRequestID else {
                return
            }
            currentRequestID = requestID
            cacheTask.take()?.cancel()
            let task = Task { @MainActor in
                await operation(requestID)
            }
            cacheTask = task
            await task.value
            if currentRequestID == requestID {
                cacheTask = nil
            }
        }

        /// Returns whether the given request still owns cache publication.
        func isCurrent(_ requestID: UInt64) -> Bool {
            requestID == currentRequestID && !Task.isCancelled
        }

        /// Updates the list of cached menu bar item window identifiers.
        @discardableResult
        func updateCachedItemIDs(
            _ itemIDs: [MenuBarItemID],
            for requestID: UInt64
        ) -> Bool {
            guard requestID == currentRequestID, !Task.isCancelled else {
                return false
            }
            cachedItemIDs = itemIDs
            return true
        }

        /// Clears the list of cached menu bar item window identifiers.
        @discardableResult
        func clearCachedItemIDs(for requestID: UInt64) -> Bool {
            guard requestID == currentRequestID, !Task.isCancelled else {
                return false
            }
            cachedItemIDs.removeAll()
            return true
        }
    }

    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// Storage for cached menu bar items, keyed by section.
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at
        /// the time this cache was created.
        let displayID: CGDirectDisplayID?

        /// The cached menu bar items as an array.
        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                guard let items = storage[section] else {
                    return
                }
                result.append(contentsOf: items)
            }
        }

        /// Creates a cache with the given display identifier.
        init(displayID: CGDirectDisplayID?) {
            self.displayID = displayID
        }

        // TODO: This is redundant now, so remove it.
        /// Returns the managed menu bar items for the given section.
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            self[section]
        }

        /// Returns the address for the menu bar item with the given tag,
        /// if it exists in the cache.
        func address(for tag: MenuBarItemTag) -> (section: MenuBarSection.Name, index: Int)? {
            for (section, items) in storage {
                guard let index = items.firstIndex(matching: tag) else {
                    continue
                }
                return (section, index)
            }
            return nil
        }

        /// Inserts the given menu bar item into the cache at the specified
        /// destination.
        mutating func insert(_ item: MenuBarItem, at destination: MoveDestination) {
            let targetTag = destination.targetItem.tag

            if targetTag == .hiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.hidden].append(item)
                case .rightOfItem:
                    self[.visible].insert(item, at: 0)
                }
                return
            }

            if targetTag == .alwaysHiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.alwaysHidden].append(item)
                case .rightOfItem:
                    self[.hidden].insert(item, at: 0)
                }
                return
            }

            guard case (let section, var index)? = address(for: targetTag) else {
                return
            }

            if case .rightOfItem = destination {
                let range = self[section].startIndex ... self[section].endIndex
                index = (index + 1).clamped(to: range)
            }

            self[section].insert(item, at: index)
        }

        /// Accesses the items in the given section.
        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { storage[section, default: []] }
            set { storage[section] = newValue }
        }
    }

    /// Returns the items to display for an Barline Bar section on the given screen.
    ///
    /// The system keeps items pushed behind a display notch in Barline's visible
    /// section, even though the user cannot see or click them. Include those
    /// items in the hidden Barline Bar without permanently changing their layout.
    func itemsForBarlineShelf(in section: MenuBarSection.Name, on screen: NSScreen) -> [MenuBarItem] {
        let sectionItems = itemCache[section]

        guard section == .hidden else {
            return sectionItems
        }

        let visibleItems = itemCache[.visible]
        let excludedIndices = Set(visibleItems.indices.filter { visibleItems[$0].isControlItem })
        let itemBounds = visibleItems.map { Optional($0.bounds) }
        let obscuredIndices = NotchOverflowResolver.obscuredIndices(
            itemBounds: itemBounds,
            excluding: excludedIndices,
            screenBounds: CGDisplayBounds(screen.displayID),
            rightSafeArea: screen.auxiliaryTopRightArea
        )
        let existingItemIDs = Set(sectionItems.map(\.stableID))
        let obscuredItems = obscuredIndices
            .map { visibleItems[$0] }
            .filter { !existingItemIDs.contains($0.stableID) }

        return sectionItems + obscuredItems
    }

    /// A pair of control items, taken from a list of menu bar items
    /// during a menu bar item cache operation.
    private struct ControlItemPair {
        let hidden: MenuBarItem
        let alwaysHidden: MenuBarItem?

        init?(items: inout [MenuBarItem]) {
            guard let hidden = items.removeFirst(matching: .hiddenControlItem) else {
                return nil
            }
            self.hidden = hidden
            alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
        }
    }

    /// Context maintained during a menu bar item cache operation.
    private struct CacheContext {
        let controlItems: ControlItemPair

        var cache: ItemCache
        var temporarilyShownItems = [(MenuBarItem, MoveDestination)]()
        var shouldClearCachedItemWindowIDs = false

        private(set) var hiddenControlItemBounds: CGRect
        private(set) var alwaysHiddenControlItemBounds: CGRect?

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            cache = ItemCache(displayID: displayID)
            hiddenControlItemBounds = Self.bestBounds(for: controlItems.hidden)
            alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map(Self.bestBounds)
        }

        static func bestBounds(for item: MenuBarItem) -> CGRect {
            item.bounds
        }

        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            if !item.canBeHidden {
                return false
            }
            if item.isSystemClone {
                return false
            }
            if item.isControlItem, item.tag != .visibleControlItem {
                return false
            }
            return true
        }

        mutating func findSection(for item: MenuBarItem) -> MenuBarSection.Name? {
            lazy var itemBounds = Self.bestBounds(for: item)
            return MenuBarSection.Name.allCases.first { section in
                switch section {
                case .visible:
                    itemBounds.minX >= hiddenControlItemBounds.maxX
                case .hidden:
                    if let alwaysHiddenControlItemBounds {
                        itemBounds.maxX <= hiddenControlItemBounds.minX &&
                            itemBounds.minX >= alwaysHiddenControlItemBounds.maxX
                    } else {
                        itemBounds.maxX <= hiddenControlItemBounds.minX
                    }
                case .alwaysHidden:
                    if let alwaysHiddenControlItemBounds {
                        itemBounds.maxX <= alwaysHiddenControlItemBounds.minX
                    } else {
                        false
                    }
                }
            }
        }
    }

    /// Caches the given menu bar items, without ensuring that the provided
    /// control items are correctly ordered.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?,
        requestID: UInt64
    ) async {
        guard
            await cacheActor.isCurrent(requestID),
            requestID == cacheRequestSequence
        else {
            return
        }

        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        for item in items where context.isValidForCaching(item) {
            if item.sourcePID == nil {
                logger.warning("Missing sourcePID for \(item.logString, privacy: .public)")
                // A few status items do not expose an extras menu bar through
                // Accessibility and can never be mapped back to a source PID.
                // Invalidating the window-ID cache here creates a feedback
                // loop that repeats the expensive lookup on every refresh.
                // Keep the UUID-tagged item stable instead; SourcePIDCache
                // throttles negative lookups and retries after its TTL.
            }

            if let temp = temporarilyShownItemContexts.first(where: { $0.tag == item.tag }) {
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
                context.temporarilyShownItems.append((item, temp.returnDestination))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            logger.warning("Couldn't find section for caching \(item.logString, privacy: .public)")
            context.shouldClearCachedItemWindowIDs = true
        }

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
        }

        if context.shouldClearCachedItemWindowIDs {
            logger.info("Clearing cached menu bar item windowIDs")
            guard
                await cacheActor.clearCachedItemIDs(for: requestID),
                requestID == cacheRequestSequence
            else {
                return
            }
        }

        guard itemCache != context.cache else {
            logger.debug("Not updating menu bar item cache, as items haven't changed")
            return
        }

        itemCache = context.cache
        logger.debug("Updated menu bar item cache")
    }

    /// Caches the current menu bar items, regardless of whether the
    /// items have changed since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsRegardless(_ currentItemIDs: [MenuBarItemID]? = nil) async {
        cacheRequestSequence += 1
        let requestID = cacheRequestSequence

        await cacheActor.runCacheTask(requestID: requestID) { [weak self] requestID in
            guard let self, let settings = appState?.settings else {
                return
            }

            guard
                await cacheActor.isCurrent(requestID),
                requestID == cacheRequestSequence
            else {
                return
            }

            guard !lastMoveOperationOccurred(within: .seconds(1)) else {
                logger.debug("Skipping menu bar item cache due to recent item movement")
                return
            }

            let environment = try? await BarlineMenuService.Connection.shared.environment()
            let displayID = environment?.activeDisplayID.map { CGDirectDisplayID($0) } ??
                NSScreen.main?.displayID
            var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let reportedItemIDs = currentItemIDs ?? items.reversed().map(\.stableID)

            guard
                await cacheActor.isCurrent(requestID),
                requestID == cacheRequestSequence
            else {
                return
            }

            let resolvedItemIDs = items.reversed().map(\.stableID)
            guard
                MenuBarRecoveryPolicy.snapshotIsComplete(
                    reportedIDs: reportedItemIDs,
                    resolvedIDs: resolvedItemIDs
                )
            else {
                logger.warning(
                    "Incomplete menu bar snapshot (reported: \(reportedItemIDs.count, privacy: .public), resolved: \(resolvedItemIDs.count, privacy: .public)); keeping previous cache"
                )
                _ = await cacheActor.clearCachedItemIDs(for: requestID)
                return
            }

            let hasVisibleControlItem = items.contains { $0.tag == .visibleControlItem }
            guard let controlItems = ControlItemPair(items: &items) else {
                // Menu bar windows can disappear briefly while Control Center
                // reparents or relayouts status items. Keep the last known-good
                // cache so the Barline Bar remains usable, but force a later retry.
                logger.warning("Missing control item for hidden section, keeping previous menu bar item cache")
                _ = await cacheActor.clearCachedItemIDs(for: requestID)
                return
            }

            guard MenuBarRecoveryPolicy.hasRequiredControlItems(
                hasVisibleControlItem: hasVisibleControlItem,
                hasAlwaysHiddenControlItem: controlItems.alwaysHidden != nil,
                requiresVisibleControlItem: settings.general.showBarlineIcon,
                requiresAlwaysHiddenControlItem: settings.advanced.enableAlwaysHiddenSection
            ) else {
                logger.warning("Missing required control item, keeping previous menu bar item cache")
                _ = await cacheActor.clearCachedItemIDs(for: requestID)
                return
            }

            guard
                await cacheActor.updateCachedItemIDs(
                    reportedItemIDs,
                    for: requestID
                ),
                requestID == cacheRequestSequence
            else {
                return
            }

            await enforceControlItemOrder(controlItems: controlItems)

            guard
                await cacheActor.isCurrent(requestID),
                requestID == cacheRequestSequence
            else {
                return
            }

            await uncheckedCacheItems(
                items: items,
                controlItems: controlItems,
                displayID: displayID,
                requestID: requestID
            )
        }
    }

    /// Caches the current menu bar items, if the items have changed
    /// since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsIfNeeded() async {
        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        let itemIDs = items.reversed().map(\.stableID)
        let environment = try? await BarlineMenuService.Connection.shared.environment()
        let displayID = environment?.activeDisplayID.map { CGDirectDisplayID($0) } ??
            NSScreen.main?.displayID
        if
            await cacheActor.cachedItemIDs != itemIDs ||
            itemCache.displayID != displayID
        {
            await cacheItemsRegardless(itemIDs)
        }
    }
}

// MARK: - Typed Item Operations

extension MenuBarItemManager {
    enum EventError: CustomStringConvertible, LocalizedError {
        case cannotComplete
        case itemNotMovable(MenuBarItem)
        case missingItemBounds(MenuBarItem)

        var description: String {
            switch self {
            case .cannotComplete:
                "\(Self.self).cannotComplete"
            case let .itemNotMovable(item):
                "\(Self.self).itemNotMovable(item: \(item.tag))"
            case let .missingItemBounds(item):
                "\(Self.self).missingItemBounds(item: \(item.tag))"
            }
        }

        var errorDescription: String? {
            switch self {
            case .cannotComplete:
                "Operation could not be completed"
            case let .itemNotMovable(item):
                "\"\(item.displayName)\" is not movable"
            case let .missingItemBounds(item):
                "Missing bounds rectangle for \"\(item.displayName)\""
            }
        }

        var recoverySuggestion: String? {
            if case .itemNotMovable = self {
                return nil
            }
            return "Please try again. If the error persists, please file a bug report."
        }
    }

    enum MoveDestination {
        case leftOfItem(MenuBarItem)
        case rightOfItem(MenuBarItem)

        var targetItem: MenuBarItem {
            switch self {
            case let .leftOfItem(item), let .rightOfItem(item): item
            }
        }

        var logString: String {
            switch self {
            case let .leftOfItem(item): "left of \(item.logString)"
            case let .rightOfItem(item): "right of \(item.logString)"
            }
        }
    }

    private nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
            !MouseHelpers.lastMovementOccurred(within: duration) &&
            !MouseHelpers.lastScrollWheelOccurred(within: duration) &&
            !MouseHelpers.isButtonPressed()
    }

    private nonisolated func waitForUserToPauseInput() async throws {
        for _ in 0 ..< 40 {
            try Task.checkCancellation()
            if hasUserPausedInput(for: .milliseconds(50)) {
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw EventError.cannotComplete
    }

    private nonisolated func eventSleep(for duration: Duration = .milliseconds(25)) async {
        let task = Task {
            try? await Task.sleep(for: duration)
        }
        await task.value
    }

    private nonisolated func getCurrentBounds(for item: MenuBarItem) async throws -> CGRect {
        let snapshot = try await BarlineMenuService.Connection.shared.snapshot()
        guard let descriptor = snapshot.items.first(where: { $0.id == item.stableID }) else {
            throw EventError.missingItemBounds(item)
        }
        return CGRect(
            x: descriptor.bounds.x,
            y: descriptor.bounds.y,
            width: descriptor.bounds.width,
            height: descriptor.bounds.height
        )
    }

    private func operation(for item: MenuBarItem, destination: MoveDestination) -> MenuBarMoveOperation? {
        let target = destination.targetItem

        let address: (section: MenuBarSection.Name, index: Int)
        if target.tag == .hiddenControlItem {
            address = switch destination {
            case .leftOfItem: (.hidden, itemCache[.hidden].count)
            case .rightOfItem: (.visible, 0)
            }
        } else if target.tag == .alwaysHiddenControlItem {
            address = switch destination {
            case .leftOfItem: (.alwaysHidden, itemCache[.alwaysHidden].count)
            case .rightOfItem: (.hidden, 0)
            }
        } else {
            guard var targetAddress = itemCache.address(for: target.tag) else {
                return nil
            }
            if case .rightOfItem = destination {
                targetAddress.index += 1
            }
            address = targetAddress
        }

        let section = switch address.section {
        case .visible: BarlineCore.MenuBarSection.visible
        case .hidden: BarlineCore.MenuBarSection.hidden
        case .alwaysHidden: BarlineCore.MenuBarSection.alwaysHidden
        }
        return MenuBarMoveOperation(itemID: item.stableID, section: section, index: address.index)
    }

    func move(item: MenuBarItem, to destination: MoveDestination) async throws {
        guard item.isMovable else {
            throw EventError.itemNotMovable(item)
        }
        guard let operation = operation(for: item, destination: destination) else {
            throw EventError.cannotComplete
        }
        try await waitForUserToPauseInput()
        logger.log("Moving \(item.logString, privacy: .public) \(destination.logString, privacy: .public)")
        lastMoveOperationTimestamp = .now
        defer { lastMoveOperationTimestamp = .now }
        do {
            _ = try await BarlineMenuService.Connection.shared.move(operation)
            await cacheItemsRegardless()
        } catch {
            logger.error("Typed helper move failed: \(error, privacy: .public)")
            throw EventError.cannotComplete
        }
    }

    func click(item: MenuBarItem, with mouseButton: CGMouseButton) async throws {
        try await waitForUserToPauseInput()
        let button: MenuBarMouseButton = switch mouseButton {
        case .left: .left
        case .right: .right
        default: .other
        }
        do {
            try await BarlineMenuService.Connection.shared.activate(item.stableID, button: button)
        } catch {
            logger.error("Typed helper activation failed: \(error, privacy: .public)")
            throw EventError.cannotComplete
        }
    }
}

// MARK: - Temporarily Showing Items

extension MenuBarItemManager {
    /// Context for a temporarily shown menu bar item.
    private final class TemporarilyShownItemContext {
        /// The tag associated with the item.
        let tag: MenuBarItemTag

        /// The destination to return the item to.
        let returnDestination: MoveDestination

        /// Helper-owned observation of the item's shown interface.
        var revealObservation: MenuBarRevealObservationToken?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        init(tag: MenuBarItemTag, returnDestination: MoveDestination) {
            self.tag = tag
            self.returnDestination = returnDestination
        }
    }

    /// Gets the destination to return the given item to after it is
    /// temporarily shown.
    private func getReturnDestination(for item: MenuBarItem, in items: [MenuBarItem]) -> MoveDestination? {
        guard let index = items.firstIndex(matching: item.tag) else {
            return nil
        }
        if items.indices.contains(index + 1) {
            return .leftOfItem(items[index + 1])
        }
        if items.indices.contains(index - 1) {
            return .rightOfItem(items[index - 1])
        }
        return nil
    }

    /// Schedules a timer for the given interval that rehides the
    /// temporarily shown items when fired.
    private func runRehideTimer(for interval: TimeInterval? = nil) {
        guard let appState else {
            return
        }
        let interval = interval ?? appState.settings.advanced.tempShowInterval
        logger.debug("Running rehide timer for interval: \(interval, format: .fixed, privacy: .public)")
        rehideTimer?.invalidate()
        rehideTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            logger.debug("Rehide timer fired")
            Task {
                await self.rehideTemporarilyShownItems()
            }
        }
    }

    /// Temporarily shows the given item.
    ///
    /// The item is cached and returned to its original location after the
    /// time interval specified by ``AdvancedSettings/tempShowInterval``.
    ///
    /// - Parameters:
    ///   - item: The item to temporarily show.
    ///   - mouseButton: The mouse button to click the item with.
    func temporarilyShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton) async {
        guard let appState else {
            logger.error("Missing AppState, so not showing \(item.logString, privacy: .public)")
            return
        }
        guard let screen = NSScreen.screenWithActiveMenuBar else {
            logger.error("No active menu bar screen, so not showing \(item.logString, privacy: .public)")
            return
        }

        guard let applicationMenuFrame = screen.getApplicationMenuFrame() else {
            logger.error("No application menu frame, so not showing \(item.logString, privacy: .public)")
            return
        }

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        guard let destination = getReturnDestination(for: item, in: items) else {
            logger.error("No return destination for \(item.logString, privacy: .public)")
            return
        }

        // Remove all items up to and including the hidden control item.
        if let index = items.firstIndex(matching: .hiddenControlItem) {
            items.removeSubrange(...index)
        }

        let maxX: CGFloat = {
            var maxX = applicationMenuFrame.maxX
            if let frameOfNotch = screen.frameOfNotch {
                maxX = max(maxX, frameOfNotch.maxX + 30)
            }
            return maxX + item.bounds.width
        }()

        // Remove items until we have enough room to show this item.
        items.trimPrefix { item in
            if item.isOnScreen, item.canBeHidden {
                return item.bounds.minX <= maxX
            }
            return true
        }

        guard let targetItem = items.first else {
            logger.warning("Not enough room to show \(item.logString, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Not enough room to show \"\(item.displayName)\""
            alert.runModal()
            return
        }

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        logger.debug("Temporarily showing \(item.logString, privacy: .public)")

        do {
            try await move(item: item, to: .leftOfItem(targetItem))
        } catch {
            logger.error("Error showing item: \(error, privacy: .public)")
            return
        }

        let context = TemporarilyShownItemContext(tag: item.tag, returnDestination: destination)
        temporarilyShownItemContexts.append(context)

        rehideTimer?.invalidate()
        defer {
            runRehideTimer()
        }

        await eventSleep(for: .milliseconds(100))
        context.revealObservation = try? await BarlineMenuService.Connection.shared
            .beginRevealObservation(for: item.stableID)

        do {
            try await click(item: item, with: mouseButton)
        } catch {
            logger.error("Error clicking item: \(error, privacy: .public)")
            return
        }

        await eventSleep(for: .milliseconds(250))
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits
    /// for the interface to close before hiding the items.
    func rehideTemporarilyShownItems() async {
        guard let appState else {
            logger.error("Missing AppState, so not rehiding")
            return
        }
        guard !temporarilyShownItemContexts.isEmpty else {
            return
        }
        for context in temporarilyShownItemContexts {
            if let token = context.revealObservation,
               await (try? BarlineMenuService.Connection.shared.revealObservationIsVisible(token)) == true
            {
                logger.debug("Menu bar item interface is shown, so waiting to rehide")
                runRehideTimer(for: 3)
                return
            }
        }
        guard hasUserPausedInput(for: .milliseconds(250)) else {
            logger.debug("Found recent user input, so waiting to rehide")
            runRehideTimer(for: 1)
            return
        }

        var currentContexts = temporarilyShownItemContexts
        temporarilyShownItemContexts.removeAll()

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedContexts = [TemporarilyShownItemContext]()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        await eventSleep(for: .milliseconds(250))

        logger.debug("Rehiding temporarily shown items")

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        while let context = currentContexts.popLast() {
            guard let item = items.first(matching: context.tag) else {
                continue
            }
            do {
                try await move(item: item, to: context.returnDestination)
                if let token = context.revealObservation {
                    await BarlineMenuService.Connection.shared.endRevealObservation(token)
                }
            } catch {
                context.rehideAttempts += 1
                logger.warning(
                    """
                    Attempt \(context.rehideAttempts, privacy: .public) to rehide \
                    \(item.logString, privacy: .public) failed with error: \
                    \(error, privacy: .public)
                    """
                )
                if context.rehideAttempts < 3 {
                    currentContexts.append(context) // Try again.
                } else {
                    // Failed contexts are ultimately added back to the array
                    // and rehidden after a longer delay, so reset the count.
                    context.rehideAttempts = 0
                    failedContexts.append(context)
                }
            }
        }

        if failedContexts.isEmpty {
            logger.debug("All items were successfully rehidden")
        } else {
            logger.error(
                """
                Some items failed to rehide: \
                \(failedContexts.map(\.tag), privacy: .public)
                """
            )
            temporarilyShownItemContexts.append(contentsOf: failedContexts.reversed())
            runRehideTimer(for: 3)
        }
    }

    /// Removes a temporarily shown item from the cache, ensuring that
    /// the item is _not_ returned to its original location.
    func removeTemporarilyShownItemFromCache(with tag: MenuBarItemTag) {
        while let index = temporarilyShownItemContexts.firstIndex(where: { $0.tag == tag }) {
            logger.debug(
                """
                Removing temporarily shown item from cache: \
                \(tag, privacy: .public)
                """
            )
            let context = temporarilyShownItemContexts.remove(at: index)
            if let token = context.revealObservation {
                Task {
                    await BarlineMenuService.Connection.shared.endRevealObservation(token)
                }
            }
        }
    }
}

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Enforces the order of the given control items, ensuring that the
    /// control item for the always-hidden section is positioned to the
    /// left of control item for the hidden section.
    private func enforceControlItemOrder(controlItems: ControlItemPair) async {
        let hidden = controlItems.hidden

        guard
            let alwaysHidden = controlItems.alwaysHidden,
            hidden.bounds.maxX <= alwaysHidden.bounds.minX
        else {
            return
        }

        do {
            logger.debug("Control items have incorrect order")
            try await move(item: alwaysHidden, to: .leftOfItem(hidden))
        } catch {
            logger.error("Error enforcing control item order: \(error, privacy: .public)")
        }
    }
}

// MARK: - Logger Helpers

private extension Logger {
    /// Logger for the menu bar item manager.
    static let menuBarItemManager = Logger(category: "MenuBarItemManager")
}
