import Foundation

/// A read-only recovery preview. It never relaxes history/rollback validation.
/// Missing identities require an explicit partial-recovery decision by the caller.
public enum WorkspaceRecoveryPlanner {
    public enum Failure: Error, Equatable, Sendable {
        case ambiguousIdentity
        case displayTopologyChanged
        case itemChangedDisplay
        case invalidLiveState
        case incompleteInventory
        case exactTargetUnavailable
    }

    public struct Preview: Equatable, Sendable {
        public let missingItemIDs: Set<MenuBarItemID>
        public let addedItemIDs: Set<MenuBarItemID>
        public let availableItemsPlan: ProfileLayoutReconciler.DisplayPlan

        /// Carries live metadata; only logical section/order is projected.
        /// Execution must verify the plan, not treat these synthetic ordinals as
        /// fresh WindowServer observations.
        public func targetSnapshot(from live: MenuBarSnapshot) throws -> MenuBarSnapshot {
            let known = Dictionary(live.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard known.count == live.items.count else { throw Failure.ambiguousIdentity }
            var items = [MenuBarItemDescriptor]()
            for target in availableItemsPlan.targets {
                for (section, ids) in [
                    (MenuBarSection.visible, target.layout.visible),
                    (.hidden, target.layout.hidden), (.alwaysHidden, target.layout.alwaysHidden),
                ] {
                    for id in ids {
                        guard let item = known[id], item.displayID == target.displayID else {
                            throw Failure.incompleteInventory
                        }
                        items.append(item.recoveryPosition(section: section, order: items.count))
                    }
                }
            }
            guard Set(items.map(\.id)) == Set(known.keys) else { throw Failure.incompleteInventory }
            return MenuBarSnapshot(
                generation: live.generation, capturedAt: live.capturedAt, items: items,
                displayIDs: live.displayIDs, displayIdentities: live.displayIdentities,
                activeSpaceIsValid: live.activeSpaceIsValid, menuTrackingIsActive: live.menuTrackingIsActive
            )
        }

        /// Even a valid available-items plan is not an exact checkpoint restore.
        public var requiresPartialRecoveryApproval: Bool {
            !missingItemIDs.isEmpty
        }
    }

    public static func preview(
        saved: MenuBarSnapshot,
        live: MenuBarSnapshot,
        destinationSupport: MenuBarMoveDestinationSupport = .existingItemRequired
    ) throws -> Preview {
        guard live.activeSpaceIsValid, !live.menuTrackingIsActive, !live.items.isEmpty else {
            throw Failure.invalidLiveState
        }
        let savedIDs = Set(saved.items.map(\.id))
        let liveIDs = Set(live.items.map(\.id))
        guard savedIDs.count == saved.items.count, liveIDs.count == live.items.count else {
            throw Failure.ambiguousIdentity
        }
        guard saved.displayIDs == live.displayIDs else { throw Failure.displayTopologyChanged }
        for identity in saved.displayIdentities ?? [] {
            guard let fingerprint = identity.hardwareFingerprint else { continue }
            guard saved.displayIdentities?.filter({ $0.hardwareFingerprint == fingerprint }).count == 1,
                  live.displayIdentities?.filter({ $0.hardwareFingerprint == fingerprint }).count == 1,
                  live.displayIdentity(for: identity.runtimeID)?.hardwareFingerprint == fingerprint
            else { throw Failure.displayTopologyChanged }
        }
        let liveByID = Dictionary(uniqueKeysWithValues: live.items.map { ($0.id, $0) })
        for item in saved.items {
            if let current = liveByID[item.id], current.displayID != item.displayID {
                throw Failure.itemChangedDisplay
            }
        }
        // Only exact identities are admitted. Similar titles or occurrence aliases
        // are not evidence that a replacement is the saved item.
        let available = saved.items.filter { liveIDs.contains($0.id) }.sorted { $0.order < $1.order }
        let layout = ProfileLayout(
            visible: available.filter { $0.section == .visible }.map(\.id),
            hidden: available.filter { $0.section == .hidden }.map(\.id),
            alwaysHidden: available.filter { $0.section == .alwaysHidden }.map(\.id)
        )
        let plan = try ProfileLayoutReconciler.planAcrossDisplays(
            layout: layout, items: live.items, destinationSupport: destinationSupport
        )
        return Preview(
            missingItemIDs: savedIDs.subtracting(liveIDs),
            addedItemIDs: liveIDs.subtracting(savedIDs),
            availableItemsPlan: plan
        )
    }

    /// Strict history and compensation must never silently accept a subset.
    /// The preview path is separate so a UI can offer explicit partial recovery.
    public static func exactPlan(
        saved: MenuBarSnapshot,
        live: MenuBarSnapshot,
        destinationSupport: MenuBarMoveDestinationSupport = .existingItemRequired
    ) throws -> ProfileLayoutReconciler.DisplayPlan {
        let result = try preview(saved: saved, live: live, destinationSupport: destinationSupport)
        guard result.missingItemIDs.isEmpty, result.addedItemIDs.isEmpty else {
            throw Failure.incompleteInventory
        }
        guard result.availableItemsPlan.matches(items: saved.items) else {
            throw Failure.exactTargetUnavailable
        }
        return result.availableItemsPlan
    }
}

private extension MenuBarItemDescriptor {
    func recoveryPosition(section: MenuBarSection, order: Int) -> Self {
        Self(
            id: id, section: section, order: order, displayID: displayID,
            isSystemItem: isSystemItem, sourceOwnership: sourceOwnership,
            isBarlineControlItem: isBarlineControlItem, tagNamespace: tagNamespace,
            title: title, displayName: displayName, ownerProcessIdentifier: ownerProcessIdentifier,
            sourceProcessIdentifier: sourceProcessIdentifier, bounds: bounds, isOnScreen: isOnScreen,
            isMovable: isMovable, canBeHidden: canBeHidden, isBentoBox: isBentoBox,
            isSystemClone: isSystemClone, isResponsive: isResponsive
        )
    }
}
