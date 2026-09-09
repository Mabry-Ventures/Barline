/// A capture belongs to one permission epoch, not merely to a granted Boolean.
/// A revoke/grant cycle invalidates pixels captured before that cycle.
public enum CapturePublicationPolicy {
    public static func permitsPublication(
        capturedGeneration: UInt64,
        currentGeneration: UInt64,
        permissionIsGranted: Bool
    ) -> Bool {
        permissionIsGranted && capturedGeneration == currentGeneration
    }
}
