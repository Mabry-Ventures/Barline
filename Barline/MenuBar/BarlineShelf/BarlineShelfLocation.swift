//
//  BarlineShelfLocation.swift
//  Barline
//

import SwiftUI

/// Locations where the Barline Bar can appear.
enum BarlineShelfLocation: Int, CaseIterable, Identifiable {
    /// The Barline Bar will appear in different locations based on context.
    case dynamic = 0

    /// The Barline Bar will appear centered below the mouse pointer.
    case mousePointer = 1

    /// The Barline Bar will appear centered below the Barline icon.
    case barlineIcon = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .dynamic: "Dynamic"
        case .mousePointer: "Mouse pointer"
        case .barlineIcon: "Barline icon"
        }
    }
}
