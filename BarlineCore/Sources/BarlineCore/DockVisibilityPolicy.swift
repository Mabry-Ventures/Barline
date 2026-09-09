public enum DockVisibilityPolicy {
    public static func usesRegularActivationPolicy(
        requestedRegular: Bool,
        hideDockIcon: Bool
    ) -> Bool {
        requestedRegular && !hideDockIcon
    }
}
