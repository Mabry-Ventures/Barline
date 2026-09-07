import Foundation

/// Captures only one verified connected display; never reassigns foreign items.
public enum DisplayVariantCapture {
    public enum Failure: Error { case unavailable, ambiguous, empty, stale }

    public static func capture(
        profile: BarlineProfile, snapshot: MenuBarSnapshot,
        displayID: MenuBarDisplayID, now: Date = Date()
    ) throws -> DisplayProfileOverride {
        guard snapshot.activeSpaceIsValid, !snapshot.menuTrackingIsActive,
              snapshot.displayIDs.contains(displayID) else { throw Failure.unavailable }
        let age = now.timeIntervalSince(snapshot.capturedAt)
        guard age >= 0, age <= 5 else { throw Failure.stale }
        let identities = snapshot.displayIdentities?.filter { $0.runtimeID == displayID } ?? []
        guard identities.count == 1, let identity = identities.first else { throw Failure.ambiguous }
        if let fingerprint = identity.hardwareFingerprint {
            guard fingerprint.isWellFormed,
                  snapshot.displayIdentities?.filter({ $0.hardwareFingerprint == fingerprint }).count == 1
            else { throw Failure.ambiguous }
        }
        let items = snapshot.items.filter { $0.displayID == displayID }.sorted { $0.order < $1.order }
        guard !items.isEmpty else { throw Failure.empty }
        let ids = Set(items.map(\.id))
        guard ids.count == items.count else { throw Failure.ambiguous }
        let groups = profile.groups.compactMap { group -> ProfileGroup? in
            let members = group.itemIDs.filter { ids.contains($0) }
            return members.isEmpty ? nil : ProfileGroup(id: group.id, name: group.name, symbol: group.symbol, itemIDs: members)
        }
        let spacers = profile.spacers.filter { spacer in
            if case let .after(id) = spacer.placement {
                return ids.contains(id)
            }
            return true
        }
        let variant = DisplayProfileOverride(
            displayID: displayID, displayFingerprint: identity.hardwareFingerprint,
            layout: ProfileLayout(
                visible: items.filter { $0.section == .visible }.map(\.id),
                hidden: items.filter { $0.section == .hidden }.map(\.id),
                alwaysHidden: items.filter { $0.section == .alwaysHidden }.map(\.id)
            ), groups: groups, spacers: spacers
        )
        var candidate = profile
        candidate.displayOverrides = [variant]
        try ProfileValidator().validate(candidate)
        return variant
    }
}
