/// The secondary shelf requires stable, always-visible system bar geometry.
/// Falling back must not rewrite the user's stored presentation preference.
public enum MenuBarPresentationPolicy {
    public static func usesShelf(requestedShelf: Bool, systemAutoHideEnabled: Bool) -> Bool {
        requestedShelf && !systemAutoHideEnabled
    }
}
