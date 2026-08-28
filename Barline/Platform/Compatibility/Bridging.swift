//
//  Bridging.swift
//  Barline
//

import Cocoa
import OSLog

typealias CGSConnectionID = Int32
typealias CGSSpaceID = Int

enum CGSSpaceType: UInt32 {
    case user = 0
    case system = 2
    case fullscreen = 4
}

struct CGSSpaceMask: OptionSet {
    let rawValue: UInt32

    static let includesCurrent = CGSSpaceMask(rawValue: 1 << 0)
    static let includesOthers = CGSSpaceMask(rawValue: 1 << 1)
    static let includesUser = CGSSpaceMask(rawValue: 1 << 2)
    static let visible = CGSSpaceMask(rawValue: 1 << 16)
    static let currentSpaceMask: CGSSpaceMask = [.includesUser, .includesCurrent]
    static let otherSpacesMask: CGSSpaceMask = [.includesOthers, .includesCurrent]
    static let allSpacesMask: CGSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
    static let allVisibleSpacesMask: CGSSpaceMask = [.visible, .allSpacesMask]
}

/// Transitional app-side facade. Unsupported work is executed by the XPC
/// compatibility service; this target contains no private symbol declarations
/// or private framework linkage.
enum Bridging {
    private static let logger = Logger(category: "CompatibilityFacade")

    struct WindowListOption: OptionSet {
        let rawValue: Int
        static let onScreen = WindowListOption(rawValue: 1 << 0)
        static let activeSpace = WindowListOption(rawValue: 1 << 1)
    }

    struct MenuBarWindowListOption: OptionSet {
        let rawValue: Int
        static let onScreen = MenuBarWindowListOption(rawValue: 1 << 0)
        static let activeSpace = MenuBarWindowListOption(rawValue: 1 << 1)
        static let itemsOnly = MenuBarWindowListOption(rawValue: 1 << 2)
    }

    static func getConnectionProperty(forKey key: String) -> Any? {
        logger.debug("Connection property read is unavailable for key \(key, privacy: .private)")
        return nil
    }

    static func setConnectionProperty(_ value: Any?, forKey key: String) {
        guard let boolean = value as? Bool else {
            logger.error("Rejected non-Boolean compatibility property value")
            return
        }
        _ = BarlineMenuService.Connection.shared.sendLegacy(
            .setConnectionProperty(key: key, value: boolean)
        )
    }

    static func getActiveMenuBarDisplayID() -> CGDirectDisplayID? {
        if
            case let .displayID(displayID) = BarlineMenuService.Connection.shared.sendLegacy(
                .activeMenuBarDisplay
            )
        {
            return displayID
        }
        return NSScreen.main?.displayID
    }

    static func isProcessUnresponsive(_ pid: pid_t) -> Bool {
        guard case let .boolean(value) = BarlineMenuService.Connection.shared.sendLegacy(
            .processIsUnresponsive(pid)
        ) else {
            return false
        }
        return value
    }

    static func setProcessUnresponsiveTimeout(_ timeout: TimeInterval) {
        _ = BarlineMenuService.Connection.shared.sendLegacy(
            .setProcessUnresponsiveTimeout(timeout)
        )
    }

    static func getActiveSpaceID() -> CGSSpaceID {
        guard case let .spaceID(value) = BarlineMenuService.Connection.shared.sendLegacy(.activeSpace) else {
            return 0
        }
        return value ?? 0
    }

    static func getCurrentSpaceID(for displayID: CGDirectDisplayID) -> CGSSpaceID? {
        guard case let .spaceID(value) = BarlineMenuService.Connection.shared.sendLegacy(
            .currentSpace(displayID: displayID)
        ) else {
            return nil
        }
        return value
    }

    static func getSpaceList(
        for windowID: CGWindowID,
        visibleSpacesOnly: Bool = false
    ) -> [CGSSpaceID] {
        _ = visibleSpacesOnly
        let activeSpace = getActiveSpaceID()
        return isWindowOnScreen(windowID) && activeSpace > 0 ? [activeSpace] : []
    }

    static func isSpaceFullscreen(_ spaceID: CGSSpaceID) -> Bool {
        guard case let .boolean(value) = BarlineMenuService.Connection.shared.sendLegacy(
            .isSpaceFullscreen(spaceID)
        ) else {
            return false
        }
        return value
    }

    static func getWindowBounds(for windowID: CGWindowID) -> CGRect? {
        guard case let .rectangle(value) = BarlineMenuService.Connection.shared.sendLegacy(
            .windowBounds(windowID)
        ) else {
            return nil
        }
        return value
    }

    static func getWindowLevel(for windowID: CGWindowID) -> CGWindowLevel? {
        guard case let .integer(value) = BarlineMenuService.Connection.shared.sendLegacy(
            .windowLevel(windowID)
        ) else {
            return nil
        }
        return value
    }

    static func isWindowOnSpace(_ windowID: CGWindowID, _ spaceID: CGSSpaceID) -> Bool {
        getSpaceList(for: windowID).contains(spaceID)
    }

    static func windowIntersectsDisplayBounds(
        _ windowID: CGWindowID,
        _ displayBounds: CGRect
    ) -> Bool {
        getWindowBounds(for: windowID).map(displayBounds.intersects) ?? false
    }

    static func isWindowOnDisplay(
        _ windowID: CGWindowID,
        _ displayID: CGDirectDisplayID
    ) -> Bool {
        windowIntersectsDisplayBounds(windowID, CGDisplayBounds(displayID))
    }

    static func isWindowOnScreen(_ windowID: CGWindowID) -> Bool {
        getWindowList(option: .onScreen).contains(windowID)
    }

    static func getWindowList(option: WindowListOption = []) -> [CGWindowID] {
        guard case let .windowIDs(values) = BarlineMenuService.Connection.shared.sendLegacy(
            .windowList(options: option.rawValue)
        ) else {
            return []
        }
        return values
    }

    static func getMenuBarWindowList(
        option: MenuBarWindowListOption = []
    ) -> [CGWindowID] {
        guard case let .windowIDs(values) = BarlineMenuService.Connection.shared.sendLegacy(
            .menuBarWindowList(options: option.rawValue)
        ) else {
            return []
        }
        return values
    }

    static func createCGWindowArray(with windowIDs: [CGWindowID]) -> CFArray? {
        var pointers: [UnsafeRawPointer?] = windowIDs.compactMap {
            UnsafeRawPointer(bitPattern: UInt($0))
        }
        guard !pointers.isEmpty else {
            return nil
        }
        return CFArrayCreate(nil, &pointers, pointers.count, nil)
    }
}
