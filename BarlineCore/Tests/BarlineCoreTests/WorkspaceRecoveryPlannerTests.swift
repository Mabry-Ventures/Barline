@testable import BarlineCore
import Foundation
import Testing

@Suite("Workspace recovery inventory preview")
struct WorkspaceRecoveryPlannerTests {
    private func item(_ name: String, order: Int = 0, display: String = "main") -> MenuBarItemDescriptor {
        MenuBarItemDescriptor(
            id: MenuBarItemID(bundleIdentifier: "test.app", title: name),
            section: .visible, order: order, displayID: MenuBarDisplayID(display)
        )
    }

    private func snapshot(_ items: [MenuBarItemDescriptor]) -> MenuBarSnapshot {
        MenuBarSnapshot(
            generation: 1, capturedAt: Date(), items: items,
            displayIDs: Set(items.compactMap(\.displayID)), activeSpaceIsValid: true
        )
    }

    @Test("An unchanged inventory needs no partial approval or move")
    func exactInventory() throws {
        let state = snapshot([item("a")])
        let result = try WorkspaceRecoveryPlanner.preview(saved: state, live: state)
        #expect(!result.requiresPartialRecoveryApproval)
        #expect(result.addedItemIDs.isEmpty)
        #expect(result.availableItemsPlan.operations.isEmpty)
        #expect(result.availableItemsPlan.matches(items: state.items))
    }

    @Test("Absent saved items are explicit and new items are preserved")
    func changedInventory() throws {
        let saved = snapshot([item("a"), item("missing", order: 1)])
        let live = snapshot([item("a"), item("new", order: 1)])
        let result = try WorkspaceRecoveryPlanner.preview(saved: saved, live: live)
        #expect(result.requiresPartialRecoveryApproval)
        #expect(result.missingItemIDs == [item("missing").id])
        #expect(result.addedItemIDs == [item("new").id])
        #expect(result.availableItemsPlan.operations.isEmpty)
        #expect(result.availableItemsPlan.matches(items: live.items))
        #expect(!result.availableItemsPlan.matches(items: [item("a")]))
        #expect(saved.items.count == 2)
    }

    @Test("Duplicate identities are rejected before planning")
    func ambiguousInventory() {
        let state = snapshot([item("a")])
        let duplicate = snapshot([item("a"), item("a", order: 1)])
        #expect(throws: WorkspaceRecoveryPlanner.Failure.ambiguousIdentity) {
            try WorkspaceRecoveryPlanner.preview(saved: duplicate, live: state)
        }
        #expect(throws: WorkspaceRecoveryPlanner.Failure.ambiguousIdentity) {
            try WorkspaceRecoveryPlanner.preview(saved: state, live: duplicate)
        }
    }

    @Test("Exact restore never silently drops missing or newly arrived identities")
    func exactRestoreRejectsInventoryChanges() {
        let one = snapshot([item("a")])
        let two = snapshot([item("a"), item("b", order: 1)])
        #expect(throws: WorkspaceRecoveryPlanner.Failure.incompleteInventory) {
            try WorkspaceRecoveryPlanner.exactPlan(saved: two, live: one)
        }
        #expect(throws: WorkspaceRecoveryPlanner.Failure.incompleteInventory) {
            try WorkspaceRecoveryPlanner.exactPlan(saved: one, live: two)
        }
    }

    @Test("Exact restore skips fixed items instead of synthesizing a drag for each descriptor")
    func fixedItemsAreNotDragged() throws {
        let fixed = MenuBarItemDescriptor(
            id: item("fixed").id, section: .visible, order: 1,
            displayID: MenuBarDisplayID("main"), isMovable: false
        )
        let state = snapshot([item("a"), fixed])
        let plan = try WorkspaceRecoveryPlanner.exactPlan(saved: state, live: state)
        #expect(plan.operations.isEmpty)
        #expect(plan.matches(items: state.items))
    }

    @Test("Display changes cannot silently relocate a checkpoint")
    func changedDisplay() {
        #expect(throws: WorkspaceRecoveryPlanner.Failure.displayTopologyChanged) {
            try WorkspaceRecoveryPlanner.preview(
                saved: snapshot([item("a")]), live: snapshot([item("a", display: "other")])
            )
        }
        #expect(throws: WorkspaceRecoveryPlanner.Failure.itemChangedDisplay) {
            try WorkspaceRecoveryPlanner.preview(
                saved: snapshot([item("a"), item("b", display: "other")]),
                live: snapshot([item("b"), item("a", display: "other")])
            )
        }
    }

    @Test("An empty response is not interpreted as every item disappearing")
    func emptyInventory() {
        #expect(throws: WorkspaceRecoveryPlanner.Failure.invalidLiveState) {
            try WorkspaceRecoveryPlanner.preview(saved: snapshot([item("a")]), live: snapshot([]))
        }
    }
}
