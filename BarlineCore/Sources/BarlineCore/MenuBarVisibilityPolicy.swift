/// WindowServer can retain an on-screen flag for a hosted status item that is
/// physically outside every display. A click at its center must reach a display
/// before the item can bypass temporary reveal.
public enum MenuBarVisibilityPolicy {
    public static func isClickable(
        reportedVisible: Bool,
        itemBounds: MenuBarRect,
        displayBounds: [MenuBarRect]
    ) -> Bool {
        guard reportedVisible, itemBounds.isFiniteAndNonnegative,
              itemBounds.width > 0, itemBounds.height > 0 else { return false }
        let centerX = itemBounds.x + itemBounds.width / 2
        let centerY = itemBounds.y + itemBounds.height / 2
        guard centerX.isFinite, centerY.isFinite else { return false }
        return displayBounds.contains { display in
            guard display.isFiniteAndNonnegative, display.width > 0, display.height > 0 else { return false }
            let maxX = display.x + display.width
            let maxY = display.y + display.height
            return maxX.isFinite && maxY.isFinite &&
                centerX >= display.x && centerX < maxX &&
                centerY >= display.y && centerY < maxY
        }
    }
}
