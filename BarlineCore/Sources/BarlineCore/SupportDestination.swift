//
//  SupportDestination.swift
//  Barline
//

import Foundation

/// A build-configured, user-opened destination. No runtime network discovery.
public enum SupportDestination {
    public static func url(from value: String?) -> URL? {
        guard let value, !value.isEmpty, value.utf8.count <= 2048,
              !value.contains("$("),
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              let components = URLComponents(string: value),
              components.scheme == "https",
              let host = components.host, host.contains("."),
              !host.hasSuffix(".invalid"), !host.hasSuffix(".example"),
              host != "example.com", host != "localhost",
              components.user == nil, components.password == nil,
              components.port == nil, components.query == nil,
              let url = components.url
        else { return nil }
        return url
    }
}
