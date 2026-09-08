@testable import BarlineCore
import Testing

@Suite("Saved layout and fixed-anchor reconciliation")
struct ProfileLayoutReconcilerTests {
    @Test("Interleaved displays translate local indices without moving foreign anchors")
    func composesDisplayPlans() throws {
        let left = MenuBarDisplayID("left")
        let right = MenuBarDisplayID("right")
        let names = ["a", "x", "b", "y", "fixedLeft", "fixedRight"]
        let items = names.enumerated().map { offset, name in
            MenuBarItemDescriptor(
                id: id(name), section: .visible, order: offset,
                displayID: offset.isMultiple(of: 2) ? left : right,
                isMovable: !name.hasPrefix("fixed")
            )
        }
        let saved = ProfileLayout(visible: ["b", "a", "fixedLeft", "y", "x", "fixedRight"].map(id))
        let plan = try ProfileLayoutReconciler.planAcrossDisplays(layout: saved, items: items)
        var live = items.map(\.id)
        for operation in plan.operations {
            let source = try #require(live.firstIndex(of: operation.itemID))
            let owner = try #require(items.first { $0.id == operation.itemID })
            #expect(owner.isMovable)
            #expect(operation.destinationDisplayID == owner.displayID)
            let insertion = operation.index - (source < operation.index ? 1 : 0)
            live.remove(at: source)
            live.insert(operation.itemID, at: insertion)
        }
        for target in plan.targets {
            let scoped = Set(items.filter { $0.displayID == target.displayID }.map(\.id))
            #expect(live.filter { scoped.contains($0) } == target.layout.visible)
        }
        #expect(plan.targets.count == 2)
        #expect(Set(live) == Set(items.map(\.id)))
    }

    @Test("A scoped display plan leaves the other display out of all operations")
    func scopesDisplayPlan() throws {
        let left = MenuBarDisplayID("left")
        let right = MenuBarDisplayID("right")
        let items = [
            MenuBarItemDescriptor(id: id("foreign"), section: .visible, order: 0, displayID: left),
            MenuBarItemDescriptor(id: id("a"), section: .visible, order: 1, displayID: right),
            MenuBarItemDescriptor(id: id("b"), section: .visible, order: 2, displayID: right),
        ]
        let plan = try ProfileLayoutReconciler.planAcrossDisplays(
            layout: ProfileLayout(visible: [id("b"), id("a")]), items: items, displayID: right
        )
        #expect(plan.targets.count == 1)
        #expect(plan.targets.first?.displayID == right)
        #expect(plan.operations.allSatisfy { $0.destinationDisplayID == right && $0.itemID != id("foreign") })
    }

    @Test("Section transfers retain physical anchors and preserve each move destination")
    func plansSectionTransfers() throws {
        let items = [
            item("a", 0), item("visibleFixed", 1, movable: false),
            item("b", 2, section: .hidden), item("hiddenFixed", 3, movable: false, section: .hidden),
        ]
        let plan = try ProfileLayoutReconciler.plan(
            layout: ProfileLayout(visible: [id("b")], hidden: [id("a")]), items: items
        )
        var live: [MenuBarSection: [MenuBarItemID]] = [
            .visible: [id("a"), id("visibleFixed")], .hidden: [id("b"), id("hiddenFixed")],
        ]
        for operation in plan.operations {
            let sourceSection = try #require(live.first { $0.value.contains(operation.itemID) }?.key)
            let sourceIndex = try #require(live[sourceSection]?.firstIndex(of: operation.itemID))
            let adjusted = operation.index - (sourceSection == operation.section && sourceIndex < operation.index ? 1 : 0)
            live[sourceSection]?.remove(at: sourceIndex)
            live[operation.section]?.insert(operation.itemID, at: adjusted)
            #expect([id("a"), id("b")].contains(operation.itemID))
        }
        #expect(live[.visible] == plan.target.visible)
        #expect(live[.hidden] == plan.target.hidden)
        #expect(plan.operations.count == 2)
    }

    @Test("A move with no physical destination fails before returning any operations")
    func rejectsEmptyDestination() {
        #expect(throws: ProfileLayoutReconciler.Failure.unsupportedDestination) {
            try ProfileLayoutReconciler.plan(layout: ProfileLayout(hidden: [id("a")]), items: [item("a", 0)])
        }
    }

    @Test("Move plans preserve fixed and unspecified anchors across every small ordering")
    func exhaustiveMovePlans() throws {
        func permutations(_ values: [String]) -> [[String]] {
            guard !values.isEmpty else { return [[]] }
            return values.flatMap { first in
                permutations(values.filter { $0 != first }).map { [first] + $0 }
            }
        }
        for currentOrder in permutations(["a", "b", "new", "fixed"]) {
            let items = currentOrder.enumerated().map { item($0.element, $0.offset, movable: $0.element != "fixed") }
            for savedOrder in permutations(["a", "b", "fixed"]) {
                let plan = try ProfileLayoutReconciler.plan(layout: ProfileLayout(visible: savedOrder.map(id)), items: items)
                var live = currentOrder.map(id)
                for operation in plan.operations {
                    #expect(operation.itemID != id("fixed"))
                    #expect(operation.itemID != id("new"))
                    let source = try #require(live.firstIndex(of: operation.itemID))
                    let insertion = operation.index - (source < operation.index ? 1 : 0)
                    live.remove(at: source)
                    live.insert(operation.itemID, at: insertion)
                }
                #expect(live == plan.target.visible)
                #expect(live.filter { $0 != id("new") } == savedOrder.map(id))
                #expect(live.filter { $0 == id("new") || $0 == id("fixed") }
                    == currentOrder.map(id).filter { $0 == id("new") || $0 == id("fixed") })
                let finalItems = live.enumerated().map {
                    MenuBarItemDescriptor(id: $0.element, section: .visible, order: $0.offset, isMovable: $0.element != id("fixed"))
                }
                #expect(try ProfileLayoutReconciler.plan(layout: ProfileLayout(visible: savedOrder.map(id)), items: finalItems).operations.isEmpty)
            }
        }
    }

    private func id(_ value: String) -> MenuBarItemID {
        MenuBarItemID(bundleIdentifier: "test.barline", accessibilityIdentifier: value)
    }

    private func item(
        _ value: String, _ order: Int, movable: Bool = true,
        section: MenuBarSection = .visible
    ) -> MenuBarItemDescriptor {
        MenuBarItemDescriptor(id: id(value), section: section, order: order, isMovable: movable)
    }

    @Test("New items remain before immovable system items instead of forcing a drag")
    func preservesNewItemsAndFixedAnchors() throws {
        let items = [item("a", 0), item("new", 1), item("b", 2),
                     item("fixed1", 3, movable: false), item("fixed2", 4, movable: false)]
        let saved = ProfileLayout(visible: ["b", "a", "fixed1", "fixed2"].map(id))
        let target = try ProfileLayoutReconciler.reconcile(layout: saved, items: items)
        #expect(target.visible == ["b", "a", "new", "fixed1", "fixed2"].map(id))
        #expect(Set(target.allItemIDs) == Set(items.map(\.id)))
    }

    @Test("Fixed anchors cannot be reordered or reassigned to another section")
    func rejectsImpossibleAnchors() {
        let items = [item("fixed1", 0, movable: false), item("fixed2", 1, movable: false)]
        #expect(throws: ProfileLayoutReconciler.Failure.immovableOrderChange) {
            try ProfileLayoutReconciler.reconcile(
                layout: ProfileLayout(visible: ["fixed2", "fixed1"].map(id)), items: items
            )
        }
        #expect(throws: ProfileLayoutReconciler.Failure.immovableSectionChange) {
            try ProfileLayoutReconciler.reconcile(layout: ProfileLayout(hidden: [id("fixed1")]), items: items)
        }
    }

    @Test("Unspecified items keep their sections while saved movable items cross sections")
    func preservesUnspecifiedSections() throws {
        let items = [item("a", 0), item("new", 1), item("hidden", 2, section: .hidden)]
        let target = try ProfileLayoutReconciler.reconcile(layout: ProfileLayout(hidden: [id("a")]), items: items)
        #expect(target.visible == [id("new")])
        #expect(target.hidden == ["a", "hidden"].map(id))
    }

    @Test("Ambiguous and absent identities fail before producing a target")
    func rejectsInvalidIdentities() {
        #expect(throws: ProfileLayoutReconciler.Failure.ambiguousIdentity) {
            try ProfileLayoutReconciler.reconcile(layout: ProfileLayout(), items: [item("a", 0), item("a", 1)])
        }
        #expect(throws: ProfileLayoutReconciler.Failure.missingItem) {
            try ProfileLayoutReconciler.reconcile(layout: ProfileLayout(visible: [id("missing")]), items: [])
        }
    }
}
