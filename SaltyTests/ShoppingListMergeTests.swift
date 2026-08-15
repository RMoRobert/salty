//
//  ShoppingListMergeTests.swift
//  SaltyTests
//
//  The merge is data-loss-critical, so these enumerate every rule from the ShoppingListMerge doc
//  comment. They mirror SaltyKMP's ShoppingListMergeTest vectors 1:1 — change them together.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct ShoppingListMergeTests {

    private let t1 = SyncWireDate.date(from: "2026-08-01T00:00:00.000Z")!
    private let t2 = SyncWireDate.date(from: "2026-08-02T00:00:00.000Z")!
    private let t3 = SyncWireDate.date(from: "2026-08-03T00:00:00.000Z")!

    private func item(_ id: String, _ text: String, done: Bool = false, heading: Bool = false, important: Bool = false) -> ShoppingListListContents {
        ShoppingListListContents(id: id, isCompleted: done, isImportant: important, isHeading: heading, text: text)
    }

    private func checklist(_ items: ShoppingListListContents..., name: String = "Groceries", date: Date? = nil) -> ServerShoppingList {
        ServerShoppingList(id: "L", name: name, isFreeform: false, contentsForList: items, lastModifiedDate: date ?? t1)
    }

    private func freeform(_ text: String, name: String = "Notes", date: Date? = nil) -> ServerShoppingList {
        ServerShoppingList(id: "L", name: name, isFreeform: true, contentsForFreeform: text, lastModifiedDate: date ?? t1)
    }

    private func resolve(_ base: ServerShoppingList?, _ local: ServerShoppingList, _ server: ServerShoppingList) -> ShoppingListMerge.Resolution {
        ShoppingListMerge.resolve(base: base, local: local, server: server, conflictCopyId: "COPY", conflictCopyLabel: "conflicted copy")
    }

    private func texts(_ l: ServerShoppingList?) -> [String]? {
        l?.contentsForList?.map(\.text)
    }

    // MARK: - Checklist: different items

    @Test func editsToDifferentItemsMergeSilently() {
        let base = checklist(item("a", "Milk"), item("b", "Eggs"))
        let local = checklist(item("a", "Milk"), item("b", "Eggs"), item("c", "Bread"), date: t2)   // added c
        let server = checklist(item("a", "Milk", done: true), item("b", "Eggs"), date: t3)          // checked a
        let r = resolve(base, local, server)
        #expect(r.conflictCopy == nil)
        #expect(texts(r.merged) == ["Milk", "Eggs", "Bread"])
        #expect(r.merged.contentsForList?.first?.isCompleted == true, "server's check-off survives")
        #expect(r.merged.lastModifiedDate == t3, "merged carries the newer date")
    }

    @Test func sameItemCheckAndTextEditBothSurvive() throws {
        let base = checklist(item("a", "Milk"))
        let local = checklist(item("a", "Milk", done: true), date: t2)          // checked it
        let server = checklist(item("a", "Whole Milk"), date: t3)               // renamed it
        let merged = try #require(resolve(base, local, server).merged.contentsForList?.first)
        #expect(merged.text == "Whole Milk")
        #expect(merged.isCompleted == true)
    }

    // MARK: - Checklist: deletions

    @Test func deleteOfAnUnchangedItemStands() {
        let base = checklist(item("a", "Milk"), item("b", "Eggs"))
        let local = checklist(item("a", "Milk"), date: t2)                      // deleted b (unchanged)
        let server = checklist(item("a", "Milk"), item("b", "Eggs"), date: t1)
        #expect(texts(resolve(base, local, server).merged) == ["Milk"])
    }

    @Test func editBeatsDeleteInBothDirections() {
        let base = checklist(item("a", "Milk"), item("b", "Eggs"))
        // Local deleted b; server edited b since base → b survives with the server's edit.
        let localDeleted = checklist(item("a", "Milk"), date: t2)
        let serverEdited = checklist(item("a", "Milk"), item("b", "Duck Eggs"), date: t3)
        #expect(texts(resolve(base, localDeleted, serverEdited).merged) == ["Milk", "Duck Eggs"])
        // Mirror image: server deleted b; local edited it.
        let localEdited = checklist(item("a", "Milk"), item("b", "Duck Eggs"), date: t3)
        let serverDeleted = checklist(item("a", "Milk"), date: t2)
        #expect(texts(resolve(base, localEdited, serverDeleted).merged) == ["Milk", "Duck Eggs"])
    }

    // MARK: - Checklist: ordering

    @Test func localAdditionsSlotInAfterTheirSurvivingPredecessor() {
        let base = checklist(item("a", "Milk"), item("b", "Eggs"))
        // Local inserted x after a, and y after b; server appended z.
        let local = checklist(item("a", "Milk"), item("x", "Butter"), item("b", "Eggs"), item("y", "Jam"), date: t2)
        let server = checklist(item("a", "Milk"), item("b", "Eggs"), item("z", "Tea"), date: t3)
        #expect(texts(resolve(base, local, server).merged) == ["Milk", "Butter", "Eggs", "Jam", "Tea"])
    }

    @Test func localAdditionAtTheFrontLandsAtTheFront() {
        let base = checklist(item("a", "Milk"))
        let local = checklist(item("x", "Butter"), item("a", "Milk"), date: t2)
        let server = checklist(item("a", "Milk"), date: t1)
        #expect(texts(resolve(base, local, server).merged) == ["Butter", "Milk"])
    }

    // MARK: - No base (legacy rows): two-way union

    @Test func noBaseUnionsAdditionsAndOrsFlags() {
        let local = checklist(item("a", "Milk", done: true), item("c", "Bread"), date: t2)
        let server = checklist(item("a", "Milk"), item("b", "Eggs"), date: t3)
        let r = resolve(nil, local, server)
        #expect(r.conflictCopy == nil)
        #expect(texts(r.merged) == ["Milk", "Bread", "Eggs"])
        #expect(r.merged.contentsForList?.first?.isCompleted == true, "no-base flag disagreement ORs: checked wins")
    }

    // MARK: - Scalars

    @Test func nameChangedOnOneSideWinsWithoutTouchingTheOtherSidesItems() {
        let base = checklist(item("a", "Milk"), name: "Groceries")
        let local = checklist(item("a", "Milk"), name: "Weekly Shop", date: t2)              // renamed
        let server = checklist(item("a", "Milk", done: true), name: "Groceries", date: t3)   // checked
        let r = resolve(base, local, server).merged
        #expect(r.name == "Weekly Shop")
        #expect(r.contentsForList?.first?.isCompleted == true)
    }

    @Test func nameChangedOnBothSidesFallsBackToNewer() {
        let base = checklist(item("a", "Milk"), name: "Groceries")
        let local = checklist(item("a", "Milk"), name: "Local Name", date: t3)
        let server = checklist(item("a", "Milk"), name: "Server Name", date: t2)
        #expect(resolve(base, local, server).merged.name == "Local Name")
    }

    // MARK: - Freeform

    @Test func freeformChangedOnOneSideMergesClean() {
        let base = freeform("v0")
        let local = freeform("v0", date: t1)
        let server = freeform("v2", date: t3)
        let r = resolve(base, local, server)
        #expect(r.conflictCopy == nil)
        #expect(r.merged.contentsForFreeform == "v2")
    }

    @Test func freeformChangedOnBothSidesPreservesLocalAsConflictCopy() throws {
        let base = freeform("v0")
        let local = freeform("local words", date: t3)
        let server = freeform("server words", date: t2)
        let r = resolve(base, local, server)
        #expect(r.merged.contentsForFreeform == "server words", "server text stays on the shared list")
        let copy = try #require(r.conflictCopy, "local text must survive as a new list")
        #expect(copy.id == "COPY")
        #expect(copy.contentsForFreeform == "local words")
        #expect(copy.name?.contains("conflicted copy") == true, "copy is visibly labeled: was '\(copy.name ?? "nil")'")
    }

    @Test func isFreeformFlipIsAWholeListConflict() throws {
        let base = checklist(item("a", "Milk"))
        let local = freeform("# now freeform", date: t3)                          // converted (newer)
        let server = checklist(item("a", "Milk", done: true), date: t2)           // kept checking items
        let r = resolve(base, local, server)
        #expect(r.merged.isFreeform == true, "newer side wins the shape")
        #expect(r.merged.contentsForFreeform == "# now freeform")
        let copy = try #require(r.conflictCopy, "the older side survives whole")
        #expect(copy.isFreeform == false)
        #expect(texts(copy) == ["Milk"])
    }

    // MARK: - Ids/revisions on outputs

    @Test func mergedAndCopyNeverCarryRevisions() {
        let base = freeform("v0")
        var local = freeform("a", date: t2)
        local.revision = 7
        local.baseRevision = 7
        var server = freeform("b", date: t3)
        server.revision = 9
        let r = resolve(base, local, server)
        #expect(r.merged.revision == nil)
        #expect(r.merged.baseRevision == nil)
        #expect(r.conflictCopy?.revision == nil)
        #expect(r.conflictCopy?.baseRevision == nil)
    }
}
