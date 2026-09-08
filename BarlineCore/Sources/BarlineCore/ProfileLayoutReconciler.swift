import Foundation

/// Merges a saved ordering with newly discovered items. Unspecified items and
/// immovable items keep their mutual order; saved movable items may move around
/// those anchors. This computes a target, not permission to synthesize events.
public enum ProfileLayoutReconciler {
    public enum Failure: Error, Equatable, Sendable {
        case ambiguousIdentity
        case missingItem
        case immovableSectionChange
        case immovableOrderChange
        case cannotHideItem
        case unsupportedDestination
    }

    public struct Plan: Equatable, Sendable {
        public let target: ProfileLayout
        public let operations: [MenuBarMoveOperation]
    }

    /// Plan one display's layout using the helper's pre-removal insertion indices.
    /// The caller must retain generation ownership and verify the complete target.
    public static func plan(
        layout: ProfileLayout,
        items: [MenuBarItemDescriptor]
    ) throws -> Plan {
        guard Set(items.map(\.displayID)).count <= 1 else {
            throw Failure.unsupportedDestination
        }
        let target = try reconcile(layout: layout, items: items)
        let selected = Set(layout.allItemIDs)
        let known = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var current = Dictionary(uniqueKeysWithValues: MenuBarSection.allCases.map { section in
            (section, items.filter { $0.section == section }.sorted { $0.order < $1.order }.map(\.id))
        })
        var operations = [MenuBarMoveOperation]()
        for (section, desired) in [
            (MenuBarSection.visible, target.visible), (.hidden, target.hidden), (.alwaysHidden, target.alwaysHidden),
        ] {
            for position in desired.indices.reversed() {
                let id = desired[position]
                guard selected.contains(id), known[id]?.isMovable == true else { continue }
                guard let sourceSection = current.first(where: { $0.value.contains(id) })?.key,
                      let sourcePosition = current[sourceSection]?.firstIndex(of: id)
                else { throw Failure.missingItem }
                let next = position + 1 < desired.count ? desired[position + 1] : nil
                let destination = current[section] ?? []
                let insertion: Int
                if let next {
                    guard let nextPosition = destination.firstIndex(of: next) else {
                        throw Failure.unsupportedDestination
                    }
                    insertion = nextPosition
                } else {
                    insertion = destination.count
                }
                let adjusted = insertion - (sourceSection == section && sourcePosition < insertion ? 1 : 0)
                if sourceSection == section, sourcePosition == adjusted {
                    continue
                }
                // The current helper needs another item as a physical destination.
                guard destination.contains(where: { $0 != id }) else {
                    throw Failure.unsupportedDestination
                }
                operations.append(MenuBarMoveOperation(
                    itemID: id, section: section, index: insertion,
                    destinationDisplayID: known[id]?.displayID
                ))
                current[sourceSection]?.remove(at: sourcePosition)
                current[section]?.insert(id, at: adjusted)
            }
        }
        guard current[.visible] == target.visible,
              current[.hidden] == target.hidden,
              current[.alwaysHidden] == target.alwaysHidden
        else { throw Failure.unsupportedDestination }
        return Plan(target: target, operations: operations)
    }

    public static func reconcile(
        layout: ProfileLayout,
        items: [MenuBarItemDescriptor]
    ) throws -> ProfileLayout {
        let requested = layout.allItemIDs
        guard Set(requested).count == requested.count,
              Set(items.map(\.id)).count == items.count
        else { throw Failure.ambiguousIdentity }
        let known = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard requested.allSatisfy({ known[$0] != nil }) else { throw Failure.missingItem }
        let selected = Set(requested)
        let sections: [(MenuBarSection, [MenuBarItemID])] = [
            (.visible, layout.visible), (.hidden, layout.hidden), (.alwaysHidden, layout.alwaysHidden),
        ]
        for (section, desired) in sections {
            for id in desired {
                guard let item = known[id] else { throw Failure.missingItem }
                if !item.isMovable, item.section != section {
                    throw Failure.immovableSectionChange
                }
                if section != .visible, !item.canBeHidden, item.section != section {
                    throw Failure.cannotHideItem
                }
            }
        }
        var merged = [MenuBarSection: [MenuBarItemID]]()
        for (section, desired) in sections {
            let anchors = items.filter {
                $0.section == section && (!selected.contains($0.id) || !$0.isMovable)
            }.sorted { $0.order < $1.order }.map(\.id)
            let fixedRequested = desired.filter { known[$0]?.isMovable == false }
            guard anchors.filter({ selected.contains($0) }) == fixedRequested else {
                throw Failure.immovableOrderChange
            }
            var result = [MenuBarItemID]()
            var anchorIndex = 0
            for id in desired {
                if known[id]?.isMovable == false {
                    // Preserve newly discovered anchors before this fixed item.
                    while anchorIndex < anchors.count {
                        let anchor = anchors[anchorIndex]
                        result.append(anchor)
                        anchorIndex += 1
                        if anchor == id {
                            break
                        }
                    }
                } else {
                    result.append(id)
                }
            }
            result.append(contentsOf: anchors.dropFirst(anchorIndex))
            merged[section] = result
        }
        return ProfileLayout(
            visible: merged[.visible] ?? [],
            hidden: merged[.hidden] ?? [],
            alwaysHidden: merged[.alwaysHidden] ?? []
        )
    }
}
