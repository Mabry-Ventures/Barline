//
//  BarlineMenuService.swift
//  Shared
//

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
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
    }
}
