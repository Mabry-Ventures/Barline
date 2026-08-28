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
        case capture([MenuBarItemID])
        case captureBackground(displayID: UInt32, sampleHeight: Double?)
        case environment
        case configureCursorInBackground(Bool)
        case pointContext(MenuBarPoint)
        case beginRevealObservation(MenuBarItemID)
        case revealObservationIsVisible(MenuBarRevealObservationToken)
        case endRevealObservation(MenuBarRevealObservationToken)
        case restore(MenuBarSnapshot)
        case health
        case restart
    }

    enum Response: Codable, Sendable {
        case start
        case capabilities(ServiceResult<MenuBarCapabilities>)
        case snapshot(ServiceResult<MenuBarSnapshot>)
        case mutation(ServiceResult<MenuBarMutationResult>)
        case activation(ServiceResult<EmptyResult>)
        case capturedImages(ServiceResult<[MenuBarCapturedImage]>)
        case background(ServiceResult<MenuBarBackgroundCapture>)
        case environment(ServiceResult<MenuBarEnvironmentSnapshot>)
        case pointContext(ServiceResult<MenuBarPointContext>)
        case revealObservation(ServiceResult<MenuBarRevealObservationToken>)
        case boolean(ServiceResult<Bool>)
        case health(MenuBarBackendHealth)
        case restart
    }

    enum ServiceResult<Value: Codable & Sendable>: Codable, Sendable {
        case success(Value)
        case failure(MenuBarBackendError)
    }

    struct EmptyResult: Codable, Sendable {}
}
