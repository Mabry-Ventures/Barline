//
//  ShelfGroupPresentation.swift
//  Barline
//

import Foundation

/// A shelf-only projection. It never changes a profile or the physical item order.
public enum ShelfGroupPresentation {
    public static func elements(
        presentation: ResolvedProfilePresentation?,
        section: MenuBarSection,
        orderedItemIDs: [MenuBarItemID],
        collapsedGroupIDs: Set<UUID> = []
    ) -> [ProfilePresentationElement] {
        var seen = Set<MenuBarItemID>()
        let ordered = orderedItemIDs.filter { seen.insert($0).inserted }
        guard var presentation else { return ordered.map(ProfilePresentationElement.item) }
        let sectionIDs: [MenuBarItemID] = switch section {
        case .visible: presentation.layout.visible
        case .hidden: presentation.layout.hidden
        case .alwaysHidden: presentation.layout.alwaysHidden
        }
        let sectionMembers = Set(sectionIDs)
        let layoutCounts = Dictionary(grouping: presentation.layout.allItemIDs, by: { $0 }).mapValues(\.count)
        let sourceCounts = Dictionary(grouping: orderedItemIDs, by: { $0 }).mapValues(\.count)
        let groupCounts = Dictionary(grouping: presentation.groups, by: \.id).mapValues(\.count)
        // Count all memberships before discarding malformed groups: an invalid
        // overlapping group must not let another group hide its ambiguous items.
        let membershipCounts = Dictionary(grouping: presentation.groups.flatMap(\.itemIDs), by: { $0 }).mapValues(\.count)
        presentation.groups = presentation.groups.filter { group in
            guard groupCounts[group.id] == 1, !group.itemIDs.isEmpty,
                  !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  group.itemIDs.allSatisfy({
                      sectionMembers.contains($0) && layoutCounts[$0] == 1 &&
                          sourceCounts[$0] == 1 && membershipCounts[$0] == 1
                  }) else { return false }
            let members = Set(group.itemIDs)
            let indices = ordered.indices.filter { members.contains(ordered[$0]) }
            guard let first = indices.first, let last = indices.last else { return false }
            // Interleaved/noncontiguous membership is ambiguous UI, not license
            // to reorder unrelated source items into or around a group.
            return indices.count == members.count && last - first + 1 == members.count
        }
        let hiddenMembers = Set(presentation.groups.filter { collapsedGroupIDs.contains($0.id) }.flatMap(\.itemIDs))
        let spacerCounts = Dictionary(grouping: presentation.spacers, by: \.id).mapValues(\.count)
        presentation.spacers = presentation.spacers.filter { spacer in
            guard spacerCounts[spacer.id] == 1, spacer.width.isFinite, spacer.width >= 0 else { return false }
            if case let .after(anchor) = spacer.placement {
                return !hiddenMembers.contains(anchor)
            }
            return true
        }
        return ProfilePresentationProjector().elements(
            presentation: presentation,
            section: section,
            orderedItemIDs: ordered
        ).filter { element in
            if case let .item(id) = element {
                return !hiddenMembers.contains(id)
            }
            return true
        }
    }
}
