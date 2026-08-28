//
//  BarlineMenuService.swift
//  Shared
//

import BarlineCore
import Foundation

enum BarlineMenuService {
    static var name: String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "BarlineMenuServiceName") as? String,
            !value.isEmpty,
            !value.contains("$(")
        else {
            return "com.mabryventures.Barline.MenuBarService"
        }
        return value
    }
}

extension BarlineMenuService {
    enum Request: Codable, Sendable {
        case start
        case capabilities
        case snapshot
        case move(MenuBarMoveOperation)
        case reveal(MenuBarItemID)
        case activate(item: MenuBarItemID, button: MenuBarMouseButton)
        case restore(MenuBarSnapshot)
        case health
        case restart
        case sourcePID(WindowInfo)
        case legacy(LegacyRequest)
    }

    enum Response: Codable, Sendable {
        case start
        case capabilities(ServiceResult<MenuBarCapabilities>)
        case snapshot(ServiceResult<MenuBarSnapshot>)
        case mutation(ServiceResult<MenuBarMutationResult>)
        case activation(ServiceResult<EmptyResult>)
        case health(MenuBarBackendHealth)
        case restart
        case sourcePID(pid_t?)
        case legacy(LegacyResponse)
    }

    enum ServiceResult<Value: Codable & Sendable>: Codable, Sendable {
        case success(Value)
        case failure(MenuBarBackendError)
    }

    struct EmptyResult: Codable, Sendable {}

    enum LegacyRequest: Codable, Sendable {
        case setConnectionProperty(key: String, value: Bool)
        case activeMenuBarDisplay
        case activeSpace
        case currentSpace(displayID: UInt32)
        case isSpaceFullscreen(Int)
        case windowBounds(UInt32)
        case windowLevel(UInt32)
        case windowList(options: Int)
        case menuBarWindowList(options: Int)
        case processIsUnresponsive(pid_t)
        case setProcessUnresponsiveTimeout(TimeInterval)
        case captureWindows(windowIDs: [UInt32], screenBounds: CGRect?, options: UInt32)
    }

    enum LegacyResponse: Codable, Sendable {
        case acknowledgement
        case displayID(UInt32?)
        case spaceID(Int?)
        case boolean(Bool)
        case rectangle(CGRect?)
        case integer(Int32?)
        case windowIDs([UInt32])
        case data(Data?)
    }
}
