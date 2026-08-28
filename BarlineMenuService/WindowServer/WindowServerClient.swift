import AppKit
import BarlineCore
import CoreGraphics
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

    private let resolver: DynamicSymbolResolver
    private let generation = OSAllocatedUnfairLock(initialState: GenerationState())

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

    func snapshot() throws -> MenuBarSnapshot {
        guard let windows = enumerateMenuBarWindows() else {
            throw MenuBarBackendError.unavailableCapability("menu bar snapshot")
        }

        let displayIDs = Set(NSScreen.screens.compactMap { screen -> MenuBarDisplayID? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
                return MenuBarDisplayID("display-\(displayID)")
            }
            let uuid = unmanagedUUID.takeRetainedValue()
            return MenuBarDisplayID(CFUUIDCreateString(nil, uuid) as String)
        })

        let descriptors = windows.enumerated().map { index, window in
            let itemID = stableID(for: window)
            return MenuBarItemDescriptor(
                id: itemID,
                section: window.isOnScreen ? .visible : .hidden,
                order: index,
                displayID: displayID(containing: window.bounds),
                isSystemItem: itemID.bundleIdentifier.hasPrefix("com.apple."),
                isBarlineControlItem: itemID.bundleIdentifier == "com.mabryventures.barline"
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
            activeSpaceIsValid: activeSpaceID() != nil
        )
    }

    func move(_ operation: MenuBarMoveOperation) throws -> MenuBarMutationResult {
        let windows = try currentWindows()
        guard let item = windows.first(where: { stableID(for: $0) == operation.itemID }) else {
            throw MenuBarBackendError.staleItem(operation.itemID)
        }
        let candidates = windows.filter { ($0.isOnScreen ? MenuBarSection.visible : .hidden) == operation.section }
        guard !candidates.isEmpty else {
            throw MenuBarBackendError.operationFailed("No destination item is available")
        }
        let targetIndex = min(max(operation.index, 0), candidates.count - 1)
        let target = candidates[targetIndex]
        try synthesizeDrag(item: item, target: target)
        let updated = try snapshot()
        return MenuBarMutationResult(generation: updated.generation, changedItemIDs: [operation.itemID])
    }

    func reveal(_ itemID: MenuBarItemID) throws -> MenuBarMutationResult {
        let windows = try currentWindows()
        guard windows.contains(where: { stableID(for: $0) == itemID }) else {
            throw MenuBarBackendError.staleItem(itemID)
        }
        let visibleCount = windows.count(where: \.isOnScreen)
        return try move(MenuBarMoveOperation(itemID: itemID, section: .visible, index: visibleCount - 1))
    }

    func activate(_ itemID: MenuBarItemID, button: MenuBarMouseButton) throws {
        let windows = try currentWindows()
        guard let item = windows.first(where: { stableID(for: $0) == itemID }) else {
            throw MenuBarBackendError.staleItem(itemID)
        }
        let sourcePID = WindowInfo(windowID: item.identifier)
            .flatMap { SourcePIDCache.shared.pid(for: $0) }
        try synthesizeClick(item: item, pid: sourcePID ?? item.ownerPID, button: button)
    }

    func restore(_ priorSnapshot: MenuBarSnapshot) throws -> MenuBarMutationResult {
        var changed = [MenuBarItemID]()
        for descriptor in priorSnapshot.items.sorted(by: { $0.order < $1.order }) {
            _ = try move(
                MenuBarMoveOperation(
                    itemID: descriptor.id,
                    section: descriptor.section,
                    index: descriptor.order
                )
            )
            changed.append(descriptor.id)
        }
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

        guard
            let array = Self.createWindowArray(identifiers),
            let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[CFString: Any]]
        else {
            return []
        }

        return descriptions.compactMap(WindowRecord.init)
            .filter { windowLevel(for: $0.identifier) != kCGMainMenuWindowLevel }
    }

    private func currentWindows() throws -> [WindowRecord] {
        guard let windows = enumerateMenuBarWindows() else {
            throw MenuBarBackendError.unavailableCapability("menu bar enumeration")
        }
        return windows
    }

    private func stableID(for window: WindowRecord) -> MenuBarItemID {
        let sourcePID = WindowInfo(windowID: window.identifier)
            .flatMap { SourcePIDCache.shared.pid(for: $0) }
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

    private func synthesizeClick(
        item: WindowRecord,
        pid: pid_t,
        button: MenuBarMouseButton
    ) throws {
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
        for event in [down, up] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            event.setIntegerValueField(windowField, value: Int64(item.identifier))
            event.postToPid(pid)
        }
    }

    private func synthesizeDrag(item: WindowRecord, target: WindowRecord) throws {
        let start = CGPoint(x: item.bounds.midX, y: item.bounds.midY)
        let end = CGPoint(x: target.bounds.midX, y: target.bounds.midY)
        let pid = WindowInfo(windowID: item.identifier)
            .flatMap { SourcePIDCache.shared.pid(for: $0) } ?? item.ownerPID
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
            let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: end, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left),
            let windowField = CGEventField(rawValue: 0x33)
        else {
            throw MenuBarBackendError.unavailableCapability("menu bar drag synthesis")
        }
        for event in [down, drag, up] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            event.setIntegerValueField(windowField, value: Int64(item.identifier))
            event.postToPid(pid)
        }
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
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(bounds) }) else {
            return nil
        }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return MenuBarDisplayID("display-\(displayID)")
        }
        return MenuBarDisplayID(CFUUIDCreateString(nil, unmanagedUUID.takeRetainedValue()) as String)
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
