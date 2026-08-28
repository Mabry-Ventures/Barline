//
//  SettingsNavigationIdentifier.swift
//  Barline
//

/// The navigation identifier type for the "Settings" interface.
enum SettingsNavigationIdentifier: String, NavigationIdentifier {
    case general = "General"
    case menuBarLayout = "Menu Bar Layout"
    case menuBarAppearance = "Menu Bar Appearance"
    case profiles = "Profiles"
    case hotkeys = "Hotkeys"
    case advanced = "Advanced"
    case about = "About"

    var iconResource: IconResource {
        switch self {
        case .general: .systemSymbol("gearshape")
        case .menuBarLayout: .systemSymbol("rectangle.topthird.inset.filled")
        case .menuBarAppearance: .systemSymbol("swatchpalette")
        case .profiles: .systemSymbol("person.crop.rectangle.stack")
        case .hotkeys: .systemSymbol("keyboard")
        case .advanced: .systemSymbol("gearshape.2")
        case .about: .assetCatalog(.barlineControlStroke)
        }
    }
}
