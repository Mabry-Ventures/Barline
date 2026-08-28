import Foundation

public enum SnapshotRejectionReason: Error, Codable, Equatable, Sendable {
    case missingDisplayGeometry
    case invalidActiveSpace
    case staleSnapshot
    case futureDatedSnapshot
    case unknownItemDisplay(MenuBarDisplayID)
    case duplicateItemIdentity(MenuBarItemID)
    case unstableItemIdentity(MenuBarItemID)
    case invalidItemGeometry(MenuBarItemID)
    case missingRequiredControlItem(MenuBarItemID)
    case implausibleItemCountCollapse(previous: Int, candidate: Int)
    case implausibleSystemItemCollapse(previous: Int, candidate: Int)
    case emptySnapshot
    case nonMonotonicGeneration(previous: UInt64, candidate: UInt64)
}

public struct SnapshotValidationPolicy: Sendable {
    public let requiredControlItemIDs: Set<MenuBarItemID>
    public let maximumAge: TimeInterval
    public let maximumFutureClockSkew: TimeInterval
    public let maximumCollapseRatio: Double
    public let maximumSystemItemCollapseRatio: Double
    public let allowsEmptySnapshot: Bool

    public init(
        requiredControlItemIDs: Set<MenuBarItemID> = [],
        maximumAge: TimeInterval = 10,
        maximumFutureClockSkew: TimeInterval = 1,
        maximumCollapseRatio: Double = 0.65,
        maximumSystemItemCollapseRatio: Double = 0.5,
        allowsEmptySnapshot: Bool = false
    ) {
        self.requiredControlItemIDs = requiredControlItemIDs
        self.maximumAge = maximumAge
        self.maximumFutureClockSkew = maximumFutureClockSkew
        self.maximumCollapseRatio = maximumCollapseRatio
        self.maximumSystemItemCollapseRatio = maximumSystemItemCollapseRatio
        self.allowsEmptySnapshot = allowsEmptySnapshot
    }
}

public struct SnapshotValidator: Sendable {
    public let policy: SnapshotValidationPolicy

    public init(policy: SnapshotValidationPolicy = SnapshotValidationPolicy()) {
        self.policy = policy
    }

    public func validate(
        _ candidate: MenuBarSnapshot,
        previous: MenuBarSnapshot?,
        now: Date = Date()
    ) -> Result<MenuBarSnapshot, SnapshotRejectionReason> {
        guard !candidate.displayIDs.isEmpty else {
            return .failure(.missingDisplayGeometry)
        }
        guard candidate.activeSpaceIsValid else {
            return .failure(.invalidActiveSpace)
        }
        let snapshotAge = now.timeIntervalSince(candidate.capturedAt)
        guard snapshotAge <= policy.maximumAge else {
            return .failure(.staleSnapshot)
        }
        guard snapshotAge >= -policy.maximumFutureClockSkew else {
            return .failure(.futureDatedSnapshot)
        }
        guard policy.allowsEmptySnapshot || !candidate.items.isEmpty else {
            return .failure(.emptySnapshot)
        }

        var seen = Set<MenuBarItemID>()
        for item in candidate.items {
            if let displayID = item.displayID, !candidate.displayIDs.contains(displayID) {
                return .failure(.unknownItemDisplay(displayID))
            }
            guard item.id.isPlausiblyStable else {
                return .failure(.unstableItemIdentity(item.id))
            }
            guard item.bounds.isFiniteAndNonnegative else {
                return .failure(.invalidItemGeometry(item.id))
            }
            guard seen.insert(item.id).inserted else {
                return .failure(.duplicateItemIdentity(item.id))
            }
        }

        let presentControlIDs = Set(
            candidate.items.lazy.filter(\.isBarlineControlItem).map(\.id)
        )
        if let missingControlID = policy.requiredControlItemIDs.subtracting(presentControlIDs).first {
            return .failure(.missingRequiredControlItem(missingControlID))
        }

        if let previous {
            guard candidate.generation > previous.generation else {
                return .failure(
                    .nonMonotonicGeneration(
                        previous: previous.generation,
                        candidate: candidate.generation
                    )
                )
            }
            if !previous.items.isEmpty {
                let retainedRatio = Double(candidate.items.count) / Double(previous.items.count)
                if retainedRatio < 1 - policy.maximumCollapseRatio {
                    return .failure(
                        .implausibleItemCountCollapse(
                            previous: previous.items.count,
                            candidate: candidate.items.count
                        )
                    )
                }
            }

            let previousSystemItemCount = previous.items.count(where: \.isSystemItem)
            if previousSystemItemCount > 0 {
                let candidateSystemItemCount = candidate.items.count(where: \.isSystemItem)
                let retainedRatio = Double(candidateSystemItemCount) / Double(previousSystemItemCount)
                if retainedRatio < 1 - policy.maximumSystemItemCollapseRatio {
                    return .failure(
                        .implausibleSystemItemCollapse(
                            previous: previousSystemItemCount,
                            candidate: candidateSystemItemCount
                        )
                    )
                }
            }
        }

        return .success(candidate)
    }
}
