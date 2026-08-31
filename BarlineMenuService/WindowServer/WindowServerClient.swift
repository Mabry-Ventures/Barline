import AppKit
import BarlineCore
import CoreGraphics
import CryptoKit
import Foundation
import os

/// The only shipping type that translates private WindowServer identifiers
/// into stable Barline domain identities.
final class WindowServerClient: @unchecked Sendable {
    typealias ConnectionID = Int32
    typealias SpaceID = Int

    private typealias MainConnectionFunction = @convention(c) () -> ConnectionID
    private typealias WindowCountFunction = @convention(c) (
        ConnectionID,
        ConnectionID,
        UnsafeMutablePointer<Int32>
    ) -> Int32
    private typealias WindowListFunction = @convention(c) (
        ConnectionID,
        ConnectionID,
        Int32,
        UnsafeMutablePointer<CGWindowID>,
        UnsafeMutablePointer<Int32>
    ) -> Int32
    private typealias WindowLevelFunction = @convention(c) (
        ConnectionID,
        CGWindowID,
        UnsafeMutablePointer<CGWindowLevel>
    ) -> Int32
    private typealias ActiveSpaceFunction = @convention(c) (ConnectionID) -> SpaceID

    private struct GenerationState {
        var value: UInt64 = 0
    }

    private struct RevealObservation {
        let sourcePID: pid_t
        let preexistingWindowIDs: Set<CGWindowID>
        var interfaceWindowID: CGWindowID?
    }

    private let resolver: DynamicSymbolResolver
    private let generation = OSAllocatedUnfairLock(initialState: GenerationState())
    private let revealObservations = OSAllocatedUnfairLock(
        initialState: [MenuBarRevealObservationToken: RevealObservation]()
    )

    init(resolver: DynamicSymbolResolver = DynamicSymbolResolver()) {
        self.resolver = resolver
    }

    var canEnumerate: Bool {
        Self.snapshotSymbols.allSatisfy(resolver.contains)
    }

    var canInterpretActiveSpace: Bool {
        resolver.contains("CGSMainConnectionID") && resolver.contains("CGSGetActiveSpace")
    }

    func behavioralProbe() -> Bool {
        guard canEnumerate else {
            return false
        }
        return enumerateMenuBarWindows() != nil
    }

    func eventSynthesisProbe() -> Bool {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: .zero,
                mouseButton: .left
            ) != nil,
            CGEventField(rawValue: 0x33) != nil
        else {
            return false
        }
        return true
    }

    func snapshot() throws -> MenuBarSnapshot {
        guard let windows = enumerateMenuBarWindows() else {
            throw MenuBarBackendError.unavailableCapability("menu bar snapshot")
        }

        let displayIdentities = NSScreen.screens.compactMap { screen -> MenuBarDisplayIdentity? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return MenuBarDisplayIdentity(
                runtimeID: stableDisplayID(displayID),
                hardwareFingerprint: hardwareFingerprint(for: displayID)
            )
        }
        let displayIDs = Set(displayIdentities.map(\.runtimeID))

        let classified = classifiedWindows(windows)
        let identifiers = identifiedWindows(windows)
        let descriptors = windows.enumerated().map { index, window in
            let itemID = identifiers[index].id
            let sourcePID = sourcePID(for: window)
            let application = NSRunningApplication(
                processIdentifier: sourcePID ?? window.ownerPID
            )
            let tagNamespace = tagNamespace(
                for: window,
                sourceApplication: application
            )
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isControlItem = tagNamespace.caseInsensitiveCompare(
                "com.mabryventures.Barline"
            ) == .orderedSame
            let semanticFlags = semanticFlags(
                namespace: tagNamespace,
                title: title ?? "",
                isControlItem: isControlItem
            )
            return MenuBarItemDescriptor(
                id: itemID,
                section: classified[index].section,
                order: index,
                displayID: displayID(containing: window.bounds),
                isSystemItem: itemID.bundleIdentifier.hasPrefix("com.apple."),
                isBarlineControlItem: isControlItem,
                tagNamespace: tagNamespace,
                title: title,
                displayName: displayName(
                    for: window,
                    application: application,
                    isControlItem: isControlItem
                ),
                ownerProcessIdentifier: window.ownerPID,
                sourceProcessIdentifier: sourcePID,
                bounds: MenuBarRect(
                    x: window.bounds.origin.x,
                    y: window.bounds.origin.y,
                    width: window.bounds.width,
                    height: window.bounds.height
                ),
                isOnScreen: window.isOnScreen,
                isMovable: semanticFlags.isMovable,
                canBeHidden: semanticFlags.canBeHidden,
                isBentoBox: semanticFlags.isBentoBox,
                isSystemClone: semanticFlags.isSystemClone,
                isResponsive: !Bridging.isProcessUnresponsive(
                    sourcePID ?? window.ownerPID
                )
            )
        }

        let nextGeneration = generation.withLock { state in
            state.value &+= 1
            return state.value
        }

        return MenuBarSnapshot(
            generation: nextGeneration,
            capturedAt: Date(),
            items: descriptors,
            displayIDs: displayIDs,
            displayIdentities: displayIdentities,
            activeSpaceIsValid: activeSpaceID() != nil
        )
    }

    func move(_ operation: MenuBarMoveOperation) async throws -> MenuBarMutationResult {
        let maximumAttempts = 8
        var lastOrigin: CGPoint?
        for attempt in 0 ..< maximumAttempts {
            try Task.checkCancellation()
            let windows = try currentWindows()
            let identified = identifiedWindows(windows)
            guard let sourceIndex = identified.firstIndex(where: { $0.id == operation.itemID }) else {
                throw MenuBarBackendError.staleItem(operation.itemID)
            }
            let item = identified[sourceIndex].window
            let classified = classifiedWindows(windows)
            let candidateIndices = classified.indices.filter {
                classified[$0].section == operation.section
            }
            guard !candidateIndices.isEmpty else {
                throw MenuBarBackendError.operationFailed("No destination item is available")
            }
            let requestedIndex = min(max(operation.index, 0), candidateIndices.count)
            let sourceDisplayID = displayID(containing: item.bounds)
            var insertionIndex = requestedIndex
            let sourcePosition = candidateIndices.firstIndex(of: sourceIndex)
            if let sourcePosition,
               sourcePosition < insertionIndex
            {
                insertionIndex -= 1
            }
            let destinationIndices = candidateIndices.filter { $0 != sourceIndex }
            insertionIndex = min(max(insertionIndex, 0), destinationIndices.count)
            if classified[sourceIndex].section == operation.section,
               sourcePosition == insertionIndex,
               operation.destinationDisplayID.map({ sourceDisplayID == $0 }) != false
            {
                let updated = try snapshot()
                return MenuBarMutationResult(
                    generation: updated.generation,
                    changedItemIDs: []
                )
            }
            guard !destinationIndices.isEmpty else {
                throw MenuBarBackendError.operationFailed("No destination item is available")
            }
            let eligibleDestinations = destinationIndices.enumerated().filter { _, index in
                operation.destinationDisplayID.map {
                    displayID(containing: classified[index].window.bounds) == $0
                } != false
            }
            guard !eligibleDestinations.isEmpty else {
                throw MenuBarBackendError.operationFailed(
                    "No destination item is available on the requested display"
                )
            }
            let targetIndex: Int
            let placement: MovePlacement
            if let following = eligibleDestinations.first(where: { offset, _ in
                offset >= insertionIndex
            }) {
                targetIndex = following.element
                placement = .left
            } else {
                targetIndex = eligibleDestinations[eligibleDestinations.count - 1].element
                placement = .right
            }
            let target = classified[targetIndex].window
            lastOrigin = item.bounds.origin
            try Task.checkCancellation()
            try await synthesizeMove(item: item, target: target, placement: placement)
            let delay = min(25 + (attempt * 20), 150)
            try await Task.sleep(for: .milliseconds(delay))
            let refreshed = try currentWindows()
            if let moved = identifiedWindows(refreshed)
                .first(where: { $0.id == operation.itemID })?.window,
                moved.bounds.origin != lastOrigin
            {
                break
            }
            if attempt == maximumAttempts - 1 {
                throw MenuBarBackendError.operationFailed("Menu bar item did not respond to move")
            }
        }
        let updated = try snapshot()
        return MenuBarMutationResult(generation: updated.generation, changedItemIDs: [operation.itemID])
    }

    func reveal(_ itemID: MenuBarItemID) async throws -> MenuBarMutationResult {
        let windows = try currentWindows()
        guard identifiedWindows(windows).contains(where: { $0.id == itemID }) else {
            throw MenuBarBackendError.staleItem(itemID)
        }
        let visibleCount = windows.count(where: \.isOnScreen)
        return try await move(MenuBarMoveOperation(itemID: itemID, section: .visible, index: visibleCount - 1))
    }

    func activate(_ itemID: MenuBarItemID, button: MenuBarMouseButton) async throws {
        let windows = try currentWindows()
        guard let item = identifiedWindows(windows).first(where: { $0.id == itemID })?.window else {
            throw MenuBarBackendError.staleItem(itemID)
        }
        let sourcePID = WindowInfo(windowID: item.identifier)
            .flatMap { SourcePIDCache.shared.pid(for: $0) }
        try await synthesizeClick(item: item, pid: sourcePID ?? item.ownerPID, button: button)
    }

    func capture(_ itemIDs: [MenuBarItemID]) throws -> [MenuBarCapturedImage] {
        guard !itemIDs.isEmpty, itemIDs.count <= 512 else {
            throw MenuBarBackendError.operationFailed("Invalid capture item count")
        }
        let windows = try currentWindows()
        let records = Dictionary(uniqueKeysWithValues: identifiedWindows(windows).map { ($0.id, $0.window) })
        return itemIDs.compactMap { itemID in
            guard
                let window = records[itemID],
                let data = WindowCaptureService.capturePNG(
                    windowIDs: [window.identifier],
                    screenBounds: nil,
                    options: CGWindowImageOption.boundsIgnoreFraming.rawValue |
                        CGWindowImageOption.bestResolution.rawValue
                )
            else {
                return nil
            }
            return MenuBarCapturedImage(
                itemID: itemID,
                pngData: data,
                bounds: MenuBarRect(
                    x: window.bounds.origin.x,
                    y: window.bounds.origin.y,
                    width: window.bounds.width,
                    height: window.bounds.height
                )
            )
        }
    }

    func captureBackground(
        displayID: UInt32,
        sampleHeight: Double?
    ) throws -> MenuBarBackgroundCapture {
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(displayID))
        guard
            let dictionaries = CGWindowListCopyWindowInfo(
                .optionOnScreenOnly,
                kCGNullWindowID
            ) as? [[CFString: Any]]
        else {
            throw MenuBarBackendError.unavailableCapability("window scene enumeration")
        }
        let windows = dictionaries.compactMap(WindowRecord.init)
        guard let menuBar = windows.first(where: { window in
            window.ownerName == "Window Server" &&
                window.layer == kCGMainMenuWindowLevel &&
                window.title == "Menubar" &&
                displayBounds.contains(window.bounds)
        }) else {
            throw MenuBarBackendError.operationFailed("No validated menu bar scene")
        }
        let wallpaper = windows.first { window in
            let application = NSRunningApplication(processIdentifier: window.ownerPID)
            return application?.bundleIdentifier == "com.apple.dock" &&
                window.title?.hasPrefix("Wallpaper") == true &&
                displayBounds.contains(window.bounds)
        }
        var captureBounds = menuBar.bounds
        if let sampleHeight {
            guard sampleHeight.isFinite, sampleHeight > 0 else {
                throw MenuBarBackendError.operationFailed("Invalid background sample height")
            }
            captureBounds.size.height = min(CGFloat(sampleHeight), menuBar.bounds.height)
        }
        let identifiers = [menuBar.identifier, wallpaper?.identifier].compactMap(\.self)
        let data = WindowCaptureService.capturePNG(
            windowIDs: identifiers,
            screenBounds: captureBounds,
            options: CGWindowImageOption.nominalResolution.rawValue
        )
        return MenuBarBackgroundCapture(
            displayID: displayID,
            menuBarBounds: MenuBarRect(
                x: menuBar.bounds.origin.x,
                y: menuBar.bounds.origin.y,
                width: menuBar.bounds.width,
                height: menuBar.bounds.height
            ),
            pngData: data
        )
    }

    func environment() -> MenuBarEnvironmentSnapshot {
        let activeSpace = Bridging.getActiveSpaceID()
        let activeDisplayID = Bridging.getActiveMenuBarDisplayID()
        return MenuBarEnvironmentSnapshot(
            activeDisplayID: activeDisplayID,
            activeStableDisplayID: activeDisplayID.map(stableDisplayID),
            activeSpaceToken: activeSpace,
            activeSpaceIsFullscreen: Bridging.isSpaceFullscreen(activeSpace)
        )
    }

    func pointContext(_ point: MenuBarPoint) throws -> MenuBarPointContext {
        let location = CGPoint(x: point.x, y: point.y)
        let isInsideItem = try currentWindows().contains { window in
            window.isOnScreen && window.bounds.contains(location)
        }
        let window = WindowInfo.createWindows(option: .onScreen)
            .filter { $0.layer < CGWindowLevelForKey(.cursorWindow) }
            .first { $0.bounds.contains(location) && $0.title?.isEmpty == false }
        let application = window?.owningApplication
        return MenuBarPointContext(
            isInsideMenuBarItem: isInsideItem,
            applicationBundleIdentifier: application?.bundleIdentifier,
            applicationIsActive: application?.isActive ?? false,
            applicationUsesRegularActivationPolicy: application?.activationPolicy == .regular
        )
    }

    static func shelfPresentationObservation(
        _ probe: MenuBarShelfPresentationProbe
    ) -> MenuBarShelfPresentationObservation {
        let roleWindows = WindowInfo.createWindows(option: .onScreen)
            .filter { $0.title == "Barline Bar" && $0.isOnScreen }
        let ownerWindows = roleWindows.filter {
            $0.ownerPID == probe.ownerProcessIdentifier
        }
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(probe.targetDisplayID))
        return MenuBarShelfPresentationObservation(
            roleIsPresentOnscreen: !roleWindows.isEmpty,
            ownerMatches: !ownerWindows.isEmpty,
            intersectsTargetDisplay: ownerWindows.contains {
                $0.bounds.intersection(displayBounds).width > 0 &&
                    $0.bounds.intersection(displayBounds).height > 0
            }
        )
    }

    func beginRevealObservation(_ itemID: MenuBarItemID) throws -> MenuBarRevealObservationToken {
        let menuBarWindows = try currentWindows()
        guard let item = identifiedWindows(menuBarWindows).first(where: { $0.id == itemID })?.window else {
            throw MenuBarBackendError.staleItem(itemID)
        }
        let pid = sourcePID(for: item) ?? item.ownerPID
        let existing = Set(WindowInfo.createWindows(option: .onScreen).map(\.windowID))
        let token = MenuBarRevealObservationToken()
        revealObservations.withLock { observations in
            observations[token] = RevealObservation(
                sourcePID: pid,
                preexistingWindowIDs: existing,
                interfaceWindowID: nil
            )
        }
        return token
    }

    func revealObservationIsVisible(_ token: MenuBarRevealObservationToken) -> Bool {
        let windows = WindowInfo.createWindows(option: .onScreen)
        return revealObservations.withLock { observations in
            guard var observation = observations[token] else { return false }
            if let interfaceWindowID = observation.interfaceWindowID {
                return windows.contains { $0.windowID == interfaceWindowID && $0.isOnScreen }
            }
            guard let interface = windows.first(where: { window in
                window.ownerPID == observation.sourcePID &&
                    !observation.preexistingWindowIDs.contains(window.windowID)
            }) else {
                return false
            }
            observation.interfaceWindowID = interface.windowID
            observations[token] = observation
            return true
        }
    }

    func endRevealObservation(_ token: MenuBarRevealObservationToken) {
        revealObservations.withLock { $0[token] = nil }
    }

    func restore(_ priorSnapshot: MenuBarSnapshot) async throws -> MenuBarMutationResult {
        guard priorSnapshot.items.count <= 256 else {
            throw MenuBarBackendError.operationFailed("restore plan exceeds the safe operation limit")
        }
        let operations = MenuBarMovePlanner().restoreOperations(for: priorSnapshot)
        guard operations.count <= 256 else {
            throw MenuBarBackendError.operationFailed("restore plan exceeds the safe operation limit")
        }
        var changed = [MenuBarItemID]()
        for operation in operations {
            try Task.checkCancellation()
            _ = try await move(operation)
            changed.append(operation.itemID)
        }
        try Task.checkCancellation()
        let updated = try snapshot()
        return MenuBarMutationResult(generation: updated.generation, changedItemIDs: changed)
    }

    private func enumerateMenuBarWindows() -> [WindowRecord]? {
        guard
            let mainConnection = resolver.resolve("CGSMainConnectionID", as: MainConnectionFunction.self),
            let getWindowCount = resolver.resolve("CGSGetWindowCount", as: WindowCountFunction.self),
            let getMenuBarList = resolver.resolve(
                "CGSGetProcessMenuBarWindowList",
                as: WindowListFunction.self
            )
        else {
            return nil
        }

        let connection = mainConnection()
        var count: Int32 = 0
        let maximumWindowCount: Int32 = 16384
        guard
            getWindowCount(connection, 0, &count) == 0,
            count > 0,
            count <= maximumWindowCount
        else {
            return []
        }

        let capacity = count
        var identifiers = [CGWindowID](repeating: 0, count: Int(capacity))
        guard
            getMenuBarList(connection, 0, capacity, &identifiers, &count) == 0,
            count >= 0,
            count <= capacity
        else {
            return nil
        }
        identifiers.removeSubrange(Int(count) ..< identifiers.count)
        if let activeSpaceID = activeSpaceID() {
            identifiers = identifiers.filter {
                Bridging.isWindowOnSpace($0, activeSpaceID)
            }
        }
        identifiers = identifiers.filter {
            windowLevel(for: $0) != kCGMainMenuWindowLevel
        }

        guard
            // CGS returns process menu bar windows from right to left. Ice
            // reverses the identifiers before assigning section-relative
            // indices; the typed move contract uses that left-to-right order.
            let array = Self.createWindowArray(Array(identifiers.reversed())),
            let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[CFString: Any]]
        else {
            return []
        }

        return descriptions.compactMap(WindowRecord.init)
    }

    private func currentWindows() throws -> [WindowRecord] {
        guard let windows = enumerateMenuBarWindows() else {
            throw MenuBarBackendError.unavailableCapability("menu bar enumeration")
        }
        return windows
    }

    private func stableID(for window: WindowRecord) -> MenuBarItemID {
        let sourcePID = sourcePID(for: window)
        let app = NSRunningApplication(processIdentifier: sourcePID ?? window.ownerPID)
        let bundleIdentifier = app?.bundleIdentifier ?? window.ownerName ?? "unknown.window-owner"
        let stableTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fingerprint = [
            window.ownerName ?? "unknown",
            stableTitle ?? "untitled",
            String(window.layer),
        ].joined(separator: ":")
        return MenuBarItemID(
            bundleIdentifier: bundleIdentifier,
            title: stableTitle,
            fallbackFingerprint: fingerprint
        )
    }

    private func identifiedWindows(
        _ windows: [WindowRecord]
    ) -> [(window: WindowRecord, id: MenuBarItemID)] {
        let baseIDs = windows.map(stableID)
        let totals = Dictionary(grouping: baseIDs, by: { $0 }).mapValues(\.count)
        var occurrences = [MenuBarItemID: Int]()
        return zip(windows, baseIDs).map { window, baseID in
            let occurrence = occurrences[baseID, default: 0]
            occurrences[baseID] = occurrence + 1
            guard totals[baseID, default: 0] > 1 else {
                return (window, baseID)
            }
            return (
                window,
                MenuBarItemID(
                    bundleIdentifier: baseID.bundleIdentifier,
                    accessibilityIdentifier: baseID.accessibilityIdentifier,
                    title: baseID.title,
                    alias: "occurrence-\(occurrence)",
                    fallbackFingerprint: baseID.fallbackFingerprint
                )
            )
        }
    }

    private func classifiedWindows(
        _ windows: [WindowRecord]
    ) -> [(window: WindowRecord, section: MenuBarSection)] {
        let hidden = windows.first { $0.title == "Barline.ControlItem.Hidden" }
        let alwaysHidden = windows.first { $0.title == "Barline.ControlItem.AlwaysHidden" }
        return windows.map { window in
            let section: MenuBarSection = switch window.title {
            case "Barline.ControlItem.AlwaysHidden": .alwaysHidden
            case "Barline.ControlItem.Hidden": .hidden
            case "Barline.ControlItem.Visible": .visible
            default:
                if let alwaysHidden, window.bounds.maxX <= alwaysHidden.bounds.minX {
                    .alwaysHidden
                } else if let hidden, window.bounds.maxX <= hidden.bounds.minX {
                    .hidden
                } else {
                    .visible
                }
            }
            return (window, section)
        }
    }

    private func sourcePID(for window: WindowRecord) -> pid_t? {
        WindowInfo(windowID: window.identifier)
            .flatMap { SourcePIDCache.shared.pid(for: $0) }
    }

    private func tagNamespace(
        for window: WindowRecord,
        sourceApplication: NSRunningApplication?
    ) -> String {
        if let namespace = sourceApplication?.bundleIdentifier ?? sourceApplication?.localizedName {
            return namespace
        }
        if let title = window.title,
           Self.barlineControlTitles.contains(title)
        {
            return "com.mabryventures.Barline"
        }
        return window.ownerName ?? "unknown.window-owner"
    }

    private func displayName(
        for window: WindowRecord,
        application: NSRunningApplication?,
        isControlItem: Bool
    ) -> String {
        if isControlItem {
            return "Barline"
        }
        let sourceName = application?.localizedName ?? application?.bundleIdentifier
        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title
        }
        return sourceName ?? "Menu Bar Item"
    }

    private func semanticFlags(
        namespace: String,
        title: String,
        isControlItem _: Bool
    ) -> (isMovable: Bool, canBeHidden: Bool, isBentoBox: Bool, isSystemClone: Bool) {
        let normalizedNamespace = namespace.lowercased()
        let isControlCenter = normalizedNamespace == "com.apple.controlcenter"
        let isBentoBox = isControlCenter && title.hasPrefix("BentoBox")
        let isClock = isControlCenter && title == "Clock"
        let isSystemClone = title == "System Status Item Clone" &&
            !normalizedNamespace.hasPrefix("com.apple.")
        let isImmovable = isClock || isBentoBox
        let explicitlyNonHideable = isControlCenter && [
            "AudioVideoModule",
            "FaceTime",
        ].contains(title) || (
            title == "Item-0" && [
                "com.apple.controlcenter",
                "com.apple.screencaptureui",
            ].contains(normalizedNamespace)
        )
        return (
            isMovable: !isImmovable,
            canBeHidden: !isImmovable && !explicitlyNonHideable,
            isBentoBox: isBentoBox,
            isSystemClone: isSystemClone
        )
    }

    private func synthesizeClick(
        item: WindowRecord,
        pid: pid_t,
        button: MenuBarMouseButton
    ) async throws {
        try Task.checkCancellation()
        let mouseButton: CGMouseButton = switch button {
        case .left: .left
        case .right: .right
        case .other: .center
        }
        let downType: CGEventType = mouseButton == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = mouseButton == .right ? .rightMouseUp : .leftMouseUp
        let point = CGPoint(x: item.bounds.midX, y: item.bounds.midY)
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: mouseButton),
            let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: mouseButton),
            let windowField = CGEventField(rawValue: 0x33)
        else {
            throw MenuBarBackendError.unavailableCapability("menu bar event synthesis")
        }
        let cursorLocation = CGEvent(source: nil)?.location
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        defer {
            if let cursorLocation {
                CGWarpMouseCursorPosition(cursorLocation)
            }
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        }
        for event in [down, up, up] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            event.setIntegerValueField(windowField, value: Int64(item.identifier))
            event.postToPid(pid)
            // Complete mouse-up even when cancellation arrives after mouse-down.
            try? await Task.sleep(for: .milliseconds(15))
        }
        try Task.checkCancellation()
    }

    private enum MovePlacement {
        case left
        case right
    }

    private func synthesizeMove(
        item: WindowRecord,
        target: WindowRecord,
        placement: MovePlacement
    ) async throws {
        try Task.checkCancellation()
        var start: CGPoint
        var end: CGPoint
        switch placement {
        case .left:
            start = CGPoint(x: target.bounds.minX, y: target.bounds.minY)
            end = start
            if item.bounds.maxX <= target.bounds.minX {
                end.x -= item.bounds.width
            } else {
                start.x -= 1
            }
        case .right:
            start = CGPoint(x: target.bounds.maxX, y: target.bounds.minY)
            end = start
            if item.bounds.minX <= target.bounds.maxX {
                end.x -= item.bounds.width
            } else {
                start.x += 1
            }
        }
        let pid = WindowInfo(windowID: item.identifier)
            .flatMap { SourcePIDCache.shared.pid(for: $0) } ?? item.ownerPID
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left),
            let windowField = CGEventField(rawValue: 0x33)
        else {
            throw MenuBarBackendError.unavailableCapability("menu bar drag synthesis")
        }
        down.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: Int64.random(in: 1 ... Int64.max))
        up.setIntegerValueField(.eventSourceUserData, value: Int64.random(in: 1 ... Int64.max))
        let cursorLocation = CGEvent(source: nil)?.location
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            if let cursorLocation {
                CGWarpMouseCursorPosition(cursorLocation)
            }
            CGDisplayShowCursor(CGMainDisplayID())
        }
        permitLocalEvents()
        for (event, identifier) in [(down, item.identifier), (up, target.identifier)] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(identifier))
            event.setIntegerValueField(
                .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                value: Int64(identifier)
            )
            event.setIntegerValueField(windowField, value: Int64(identifier))
        }

        let initialOrigin = item.bounds.origin
        do {
            try await deliver(down, to: pid)
            guard let draggedOrigin = try await waitForOriginChange(
                of: item.identifier,
                from: initialOrigin,
                timeout: .milliseconds(200)
            ) else {
                throw MenuBarBackendError.operationFailed("Menu bar item did not respond to move")
            }
            try await deliver(up, to: pid)
            try await deliver(up, to: pid)
            // Some hosted status items settle directly at their final origin
            // after mouse-up and therefore have no second geometry transition.
            // Event delivery has completed; the outer move loop and the typed
            // coordinator postcondition verify the final placement.
            _ = try await waitForOriginChange(
                of: item.identifier,
                from: draggedOrigin,
                timeout: .milliseconds(200)
            )
        } catch {
            // Always complete mouse-up after a successful or partially
            // successful mouse-down so the item cannot remain grabbed.
            let cleanup = Task.detached { [self] in
                try? await deliver(up, to: pid)
                try? await deliver(up, to: pid)
            }
            await cleanup.value
            throw error
        }
        try Task.checkCancellation()
    }

    private func waitForOriginChange(
        of identifier: CGWindowID,
        from origin: CGPoint,
        timeout: Duration
    ) async throws -> CGPoint? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            if let current = try currentWindows().first(where: { $0.identifier == identifier })?.bounds.origin,
               current != origin
            {
                return current
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }

    /// Routes a menu bar event through both the session and target-process
    /// event streams. A direct `postToPid` reaches the hosted status-item
    /// process on macOS 26 but does not trigger its movement behavior.
    private func deliver(_ event: CGEvent, to pid: pid_t) async throws {
        guard let entry = uniqueNullEvent(), let exit = uniqueNullEvent() else {
            throw MenuBarBackendError.unavailableCapability("menu bar event delivery")
        }
        let delivery = HelperEventDelivery()
        let fields: [CGEventField] = [
            .eventSourceUserData,
            .mouseEventWindowUnderMousePointer,
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            CGEventField(rawValue: 0x33)!, // swiftlint:disable:this force_unwrapping
        ]

        let processControlTap = HelperEventTap(
            type: .null,
            location: .process(pid),
            placement: .headInsertEventTap,
            // A passive control tap keeps the XPC service from needing its own
            // separate Accessibility grant. Null signals are harmless if they
            // continue through the target process's event stream.
            options: .listenOnly
        ) { _, received in
            if self.event(received, matches: entry, fields: [.eventSourceUserData]) {
                event.post(tap: .cgSessionEventTap)
                return nil
            }
            if self.event(received, matches: exit, fields: [.eventSourceUserData]) {
                delivery.finish()
                return nil
            }
            return received
        }
        let sessionTap = HelperEventTap(
            type: event.type,
            location: .session,
            placement: .tailAppendEventTap,
            options: .listenOnly
        ) { tap, received in
            guard self.event(received, matches: event, fields: fields) else {
                return received
            }
            tap.disable()
            event.postToPid(pid)
            received.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            return received
        }
        let processEventTap = HelperEventTap(
            type: event.type,
            location: .process(pid),
            placement: .headInsertEventTap,
            options: .listenOnly
        ) { tap, received in
            guard self.event(received, matches: event, fields: fields) else {
                return received
            }
            tap.disable()
            exit.postToPid(pid)
            received.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            return received
        }

        do {
            try await delivery.run(
                taps: [processControlTap, sessionTap, processEventTap],
                timeout: .milliseconds(500)
            ) {
                entry.postToPid(pid)
            }
        } catch let HelperEventDelivery.DeliveryError.unavailable(stage) {
            let listenAllowed = CGPreflightListenEventAccess()
            let postAllowed = CGPreflightPostEventAccess()
            throw MenuBarBackendError.operationFailed(
                "Menu bar event delivery unavailable at stage \(stage) " +
                    "(listen: \(listenAllowed), post: \(postAllowed))"
            )
        } catch HelperEventDelivery.DeliveryError.timedOut {
            throw MenuBarBackendError.operationFailed("Menu bar event delivery timed out")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MenuBarBackendError.operationFailed("Menu bar event delivery failed")
        }
    }

    private func uniqueNullEvent() -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.setIntegerValueField(
            .eventSourceUserData,
            value: Int64.random(in: 1 ... Int64.max)
        )
        return event
    }

    private func event(
        _ lhs: CGEvent,
        matches rhs: CGEvent,
        fields: [CGEventField]
    ) -> Bool {
        fields.allSatisfy {
            lhs.getIntegerValueField($0) == rhs.getIntegerValueField($0)
        }
    }

    private func permitLocalEvents() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let mask: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents,
        ]
        source.setLocalEventsFilterDuringSuppressionState(
            mask,
            state: .eventSuppressionStateRemoteMouseDrag
        )
        source.setLocalEventsFilterDuringSuppressionState(
            mask,
            state: .eventSuppressionStateSuppressionInterval
        )
        source.localEventsSuppressionInterval = 0
    }

    private func windowLevel(for identifier: CGWindowID) -> CGWindowLevel? {
        guard
            let mainConnection = resolver.resolve("CGSMainConnectionID", as: MainConnectionFunction.self),
            let getWindowLevel = resolver.resolve("CGSGetWindowLevel", as: WindowLevelFunction.self)
        else {
            return nil
        }
        var level: CGWindowLevel = 0
        guard getWindowLevel(mainConnection(), identifier, &level) == 0 else {
            return nil
        }
        return level
    }

    private func activeSpaceID() -> SpaceID? {
        guard
            let mainConnection = resolver.resolve("CGSMainConnectionID", as: MainConnectionFunction.self),
            let getActiveSpace = resolver.resolve("CGSGetActiveSpace", as: ActiveSpaceFunction.self)
        else {
            return nil
        }
        let value = getActiveSpace(mainConnection())
        return value > 0 ? value : nil
    }

    private func displayID(containing bounds: CGRect) -> MenuBarDisplayID? {
        let match = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGFloat)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let intersection = CGDisplayBounds(displayID).intersection(bounds)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
                return nil
            }
            return (displayID, intersection.width * intersection.height)
        }.max { $0.1 < $1.1 }
        return match.map { stableDisplayID($0.0) }
    }

    private func stableDisplayID(_ displayID: CGDirectDisplayID) -> MenuBarDisplayID {
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return MenuBarDisplayID("display-\(displayID)")
        }
        return MenuBarDisplayID(CFUUIDCreateString(nil, unmanagedUUID.takeRetainedValue()) as String)
    }

    private func hardwareFingerprint(
        for displayID: CGDirectDisplayID
    ) -> MenuBarDisplayHardwareFingerprint? {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        let unknownVendor: UInt32 = 0x756E_6B6E // `unkn`
        let genericProduct: UInt32 = 0x0717
        guard vendor != 0,
              vendor != unknownVendor,
              model != 0,
              model != genericProduct,
              serial != 0
        else { return nil }

        var payload = Data("com.mabryventures.Barline.display-fingerprint.v1\0".utf8)
        for component in [vendor, model, serial] {
            var bigEndian = component.bigEndian
            withUnsafeBytes(of: &bigEndian) { payload.append(contentsOf: $0) }
        }
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return MenuBarDisplayHardwareFingerprint("v1:\(digest)")
    }

    private static func createWindowArray(_ identifiers: [CGWindowID]) -> CFArray? {
        var pointers: [UnsafeRawPointer?] = identifiers.compactMap {
            UnsafeRawPointer(bitPattern: UInt($0))
        }
        guard !pointers.isEmpty else {
            return nil
        }
        return CFArrayCreate(nil, &pointers, pointers.count, nil)
    }

    private static let snapshotSymbols = [
        "CGSMainConnectionID",
        "CGSGetWindowCount",
        "CGSGetProcessMenuBarWindowList",
        "CGSGetWindowLevel",
        "CGSGetActiveSpace",
        "CGSCopySpacesForWindows",
    ]

    private static let barlineControlTitles: Set<String> = [
        "Barline.ControlItem.Visible",
        "Barline.ControlItem.Hidden",
        "Barline.ControlItem.AlwaysHidden",
    ]
}

private struct WindowRecord {
    let identifier: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect
    let layer: Int
    let title: String?
    let ownerName: String?
    let isOnScreen: Bool

    init?(_ dictionary: [CFString: Any]) {
        guard
            let identifier = dictionary[kCGWindowNumber] as? CGWindowID,
            let ownerPID = dictionary[kCGWindowOwnerPID] as? pid_t,
            let boundsDictionary = dictionary[kCGWindowBounds] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
            let layer = dictionary[kCGWindowLayer] as? Int
        else {
            return nil
        }
        self.identifier = identifier
        self.ownerPID = ownerPID
        self.bounds = bounds
        self.layer = layer
        title = dictionary[kCGWindowName] as? String
        ownerName = dictionary[kCGWindowOwnerName] as? String
        isOnScreen = dictionary[kCGWindowIsOnscreen] as? Bool ?? false
    }
}
