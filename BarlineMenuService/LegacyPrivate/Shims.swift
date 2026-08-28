//
//  Shims.swift
//  Shared
//

import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import os

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

/// Transitional compatibility resolver. The call sites using these wrappers
/// are being migrated to typed XPC requests; until that migration completes,
/// every missing symbol safely degrades instead of crashing at process load.
private final class LegacyDynamicSymbols: @unchecked Sendable {
    private struct Storage: Sendable {
        var handles = [UInt]()
        var symbols = [String: UInt]()
        var missing = Set<String>()
    }

    static let shared = LegacyDynamicSymbols()
    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    private init() {}

    deinit {
        storage.withLock { storage in
            for address in storage.handles {
                if let handle = UnsafeMutableRawPointer(bitPattern: address) {
                    dlclose(handle)
                }
            }
        }
    }

    func resolve<T>(_ name: String, as type: T.Type) -> T? {
        guard
            let address = address(of: name),
            let pointer = UnsafeMutableRawPointer(bitPattern: address)
        else {
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }

    private func address(of name: String) -> UInt? {
        storage.withLock { storage in
            if let address = storage.symbols[name] {
                return address
            }
            if storage.missing.contains(name) {
                return nil
            }
            if storage.handles.isEmpty {
                let libraryPaths: [String] = [
                    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                    "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
                ]
                storage.handles = libraryPaths.compactMap { path in
                    dlopen(path, RTLD_NOW | RTLD_LOCAL).map { UInt(bitPattern: $0) }
                }
            }
            for handleAddress in storage.handles {
                guard let handle = UnsafeMutableRawPointer(bitPattern: handleAddress) else {
                    continue
                }
                if let pointer = dlsym(handle, name) {
                    let address = UInt(bitPattern: pointer)
                    storage.symbols[name] = address
                    return address
                }
            }
            storage.missing.insert(name)
            return nil
        }
    }
}

private typealias MainConnectionFunction = @convention(c) () -> CGSConnectionID
private typealias CopyConnectionPropertyFunction = @convention(c) (
    CGSConnectionID,
    CGSConnectionID,
    CFString,
    UnsafeMutablePointer<Unmanaged<CFTypeRef>?>
) -> CGError
private typealias SetConnectionPropertyFunction = @convention(c) (
    CGSConnectionID,
    CGSConnectionID,
    CFString,
    CFTypeRef
) -> CGError
private typealias ActiveMenuBarDisplayFunction = @convention(c) (
    CGSConnectionID
) -> Unmanaged<CFString>?
private typealias AppUnresponsiveFunction = @convention(c) (
    CGSConnectionID,
    UnsafeMutablePointer<ProcessSerialNumber>
) -> Bool
private typealias SetUnresponsiveTimeoutFunction = @convention(c) (CGSConnectionID, Double) -> CGError
private typealias ActiveSpaceFunction = @convention(c) (CGSConnectionID) -> CGSSpaceID
private typealias SpacesForWindowsFunction = @convention(c) (
    CGSConnectionID,
    UInt32,
    CFArray
) -> Unmanaged<CFArray>?
private typealias CurrentSpaceFunction = @convention(c) (
    CGSConnectionID,
    CFString
) -> CGSSpaceID
private typealias SpaceTypeFunction = @convention(c) (CGSConnectionID, CGSSpaceID) -> UInt32
private typealias WindowCountFunction = @convention(c) (
    CGSConnectionID,
    CGSConnectionID,
    UnsafeMutablePointer<Int32>
) -> CGError
private typealias WindowListFunction = @convention(c) (
    CGSConnectionID,
    CGSConnectionID,
    Int32,
    UnsafeMutablePointer<CGWindowID>,
    UnsafeMutablePointer<Int32>
) -> CGError
private typealias WindowBoundsFunction = @convention(c) (
    CGSConnectionID,
    CGWindowID,
    UnsafeMutablePointer<CGRect>
) -> CGError
private typealias WindowLevelFunction = @convention(c) (
    CGSConnectionID,
    CGWindowID,
    UnsafeMutablePointer<CGWindowLevel>
) -> CGError
private typealias ProcessForPIDFunction = @convention(c) (
    pid_t,
    UnsafeMutablePointer<ProcessSerialNumber>
) -> OSStatus

private let unavailableCGError: CGError = .init(rawValue: 1000) ?? .failure

func CGSMainConnectionID() -> CGSConnectionID {
    LegacyDynamicSymbols.shared.resolve("CGSMainConnectionID", as: MainConnectionFunction.self)?() ?? 0
}

func CGSDefaultConnectionForThread() -> CGSConnectionID {
    LegacyDynamicSymbols.shared.resolve("CGSDefaultConnectionForThread", as: MainConnectionFunction.self)?() ?? 0
}

func CGSCopyConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ outValue: inout Unmanaged<CFTypeRef>?
) -> CGError {
    guard let function = LegacyDynamicSymbols.shared.resolve(
        "CGSCopyConnectionProperty",
        as: CopyConnectionPropertyFunction.self
    ) else {
        return unavailableCGError
    }
    return function(cid, targetCID, key, &outValue)
}

func CGSSetConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError {
    guard let function = LegacyDynamicSymbols.shared.resolve(
        "CGSSetConnectionProperty",
        as: SetConnectionPropertyFunction.self
    ) else {
        return unavailableCGError
    }
    return function(cid, targetCID, key, value)
}

func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: CGSConnectionID) -> Unmanaged<CFString>? {
    LegacyDynamicSymbols.shared.resolve(
        "CGSCopyActiveMenuBarDisplayIdentifier",
        as: ActiveMenuBarDisplayFunction.self
    )?(cid)
}

func CGSEventIsAppUnresponsive(
    _ cid: CGSConnectionID,
    _ psn: inout ProcessSerialNumber
) -> Bool {
    LegacyDynamicSymbols.shared.resolve(
        "CGSEventIsAppUnresponsive",
        as: AppUnresponsiveFunction.self
    )?(cid, &psn) ?? false
}

func CGSEventSetAppIsUnresponsiveNotificationTimeout(
    _ cid: CGSConnectionID,
    _ timeout: Double
) -> CGError {
    LegacyDynamicSymbols.shared.resolve(
        "CGSEventSetAppIsUnresponsiveNotificationTimeout",
        as: SetUnresponsiveTimeoutFunction.self
    )?(cid, timeout) ?? unavailableCGError
}

func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID {
    LegacyDynamicSymbols.shared.resolve("CGSGetActiveSpace", as: ActiveSpaceFunction.self)?(cid) ?? 0
}

func CGSCopySpacesForWindows(
    _ cid: CGSConnectionID,
    _ mask: CGSSpaceMask,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>? {
    LegacyDynamicSymbols.shared.resolve(
        "CGSCopySpacesForWindows",
        as: SpacesForWindowsFunction.self
    )?(cid, mask.rawValue, windowIDs)
}

func CGSManagedDisplayGetCurrentSpace(
    _ cid: CGSConnectionID,
    _ displayUUID: CFString
) -> CGSSpaceID {
    LegacyDynamicSymbols.shared.resolve(
        "CGSManagedDisplayGetCurrentSpace",
        as: CurrentSpaceFunction.self
    )?(cid, displayUUID) ?? 0
}

func CGSSpaceGetType(_ cid: CGSConnectionID, _ sid: CGSSpaceID) -> CGSSpaceType {
    let rawValue = LegacyDynamicSymbols.shared.resolve(
        "CGSSpaceGetType",
        as: SpaceTypeFunction.self
    )?(cid, sid)
    return rawValue.flatMap(CGSSpaceType.init(rawValue:)) ?? .user
}

func CGSGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError {
    windowCountFunction(named: "CGSGetWindowCount", cid, targetCID, &outCount)
}

func CGSGetOnScreenWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError {
    windowCountFunction(named: "CGSGetOnScreenWindowCount", cid, targetCID, &outCount)
}

private func windowCountFunction(
    named name: String,
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError {
    guard let function = LegacyDynamicSymbols.shared.resolve(name, as: WindowCountFunction.self) else {
        outCount = 0
        return unavailableCGError
    }
    return function(cid, targetCID, &outCount)
}

func CGSGetWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError {
    windowListFunction(named: "CGSGetWindowList", cid, targetCID, count, list, &outCount)
}

func CGSGetOnScreenWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError {
    windowListFunction(named: "CGSGetOnScreenWindowList", cid, targetCID, count, list, &outCount)
}

func CGSGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError {
    windowListFunction(named: "CGSGetProcessMenuBarWindowList", cid, targetCID, count, list, &outCount)
}

private func windowListFunction(
    named name: String,
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError {
    guard let function = LegacyDynamicSymbols.shared.resolve(name, as: WindowListFunction.self) else {
        outCount = 0
        return unavailableCGError
    }
    return function(cid, targetCID, count, list, &outCount)
}

func CGSGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError {
    guard let function = LegacyDynamicSymbols.shared.resolve(
        "CGSGetScreenRectForWindow",
        as: WindowBoundsFunction.self
    ) else {
        return unavailableCGError
    }
    return function(cid, wid, &outRect)
}

func CGSGetWindowLevel(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outLevel: inout CGWindowLevel
) -> CGError {
    guard let function = LegacyDynamicSymbols.shared.resolve(
        "CGSGetWindowLevel",
        as: WindowLevelFunction.self
    ) else {
        return unavailableCGError
    }
    return function(cid, wid, &outLevel)
}

func GetProcessForPID(_ pid: pid_t, _ psn: inout ProcessSerialNumber) -> OSStatus {
    LegacyDynamicSymbols.shared.resolve(
        "GetProcessForPID",
        as: ProcessForPIDFunction.self
    )?(pid, &psn) ?? OSStatus(paramErr)
}
