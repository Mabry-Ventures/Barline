/// The secondary shelf requires stable, always-visible system bar geometry.
/// Falling back must not rewrite the user's stored presentation preference.
public enum MenuBarPresentationPolicy {
    /// A picker must not compete with the item being revealed or restored.
    public static func allowsPresentation(activating: Bool, restoring: Bool) -> Bool {
        !activating && !restoring
    }

    /// Keep layout authority intact while projecting only items not currently
    /// loaned to the native menu bar. A failed restore retains the exclusion.
    public static func shelfItemIDs(
        _ orderedIDs: [MenuBarItemID], temporarilyRevealed: Set<MenuBarItemID>
    ) -> [MenuBarItemID] {
        orderedIDs.filter { !temporarilyRevealed.contains($0) }
    }

    public static func usesShelf(requestedShelf: Bool, systemAutoHideEnabled: Bool) -> Bool {
        requestedShelf && !systemAutoHideEnabled
    }
}

/// Transport acknowledgement is not proof of a menu or direct action.
public enum MenuBarItemActivationOutcome: Equatable, Sendable {
    case interfaceObserved
    case interfaceNotObserved
    case failed
}
