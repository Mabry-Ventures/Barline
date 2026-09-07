import Foundation

/// Closed diagnostic vocabulary. Never include an error's associated payload,
/// description, userInfo, identity, title, path, or a nested error in a log.
public enum PrivacySafeDiagnostics {
    public static func errorCode(_ error: any Error) -> String {
        guard let backendError = error as? MenuBarBackendError else {
            if error is CancellationError {
                return "cancelled"
            }
            if error is DecodingError {
                return "decode_failed"
            }
            if error is EncodingError {
                return "encode_failed"
            }
            return "operation_failed"
        }
        switch backendError {
        case .unavailableCapability: return "capability_unavailable"
        case .staleItem: return "stale_item"
        case .unsafeMenuTracking: return "menu_tracking_active"
        case let .invalidSnapshot(reason): return snapshotCode(reason)
        case .interrupted: return "helper_interrupted"
        case .timedOut: return "helper_timed_out"
        case .operationFailed: return "operation_failed"
        }
    }

    private static func snapshotCode(_ reason: SnapshotRejectionReason) -> String {
        switch reason {
        case .missingDisplayGeometry: "snapshot_missing_display"
        case .invalidActiveSpace: "snapshot_invalid_space"
        case .staleSnapshot: "snapshot_stale"
        case .futureDatedSnapshot: "snapshot_future_dated"
        case .unknownItemDisplay: "snapshot_unknown_display"
        case .displayIdentitySetMismatch: "snapshot_display_mismatch"
        case .duplicateDisplayIdentity: "snapshot_duplicate_display"
        case .malformedDisplayFingerprint: "snapshot_invalid_display"
        case .duplicateItemIdentity: "snapshot_duplicate_item"
        case .unstableItemIdentity: "snapshot_unstable_item"
        case .invalidItemGeometry: "snapshot_invalid_geometry"
        case .missingRequiredControlItem: "snapshot_missing_control"
        case .implausibleItemCountCollapse: "snapshot_item_collapse"
        case .implausibleSystemItemCollapse: "snapshot_system_item_collapse"
        case .emptySnapshot: "snapshot_empty"
        case .nonMonotonicGeneration: "snapshot_stale_generation"
        }
    }
}
