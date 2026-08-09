//
//  ShoppingListLogicTests.swift
//  SaltyTests
//
//  Covers the checklist logic behind the shopping list UI: the freeform-Markdown → checklist
//  conversion (legacy lists, including the migration-0002 seeded default) and the pure item-array
//  operations the view model delegates to.
//

import Testing
@testable import Salty

struct ShoppingListFreeformConverterTests {

    @Test func convertsSeededDefaultListTemplate() {
        // The exact freeform contents migration 0002 seeds into a fresh database.
        let items = ShoppingListFreeformConverter.items(from: "# Shopping List\n\n##Store Name\n* Item Name")
        #expect(items.count == 3)
        #expect(items[0].isHeading == true)
        #expect(items[0].text == "Shopping List")
        #expect(items[1].isHeading == true)
        #expect(items[1].text == "Store Name")
        #expect(items[2].isHeading == false)
        #expect(items[2].text == "Item Name")
    }

    @Test func parsesBulletVariantsAndPlainLines() {
        let items = ShoppingListFreeformConverter.items(from: "* milk\n- eggs\n+ butter\n• bread\nplain line")
        #expect(items.map(\.text) == ["milk", "eggs", "butter", "bread", "plain line"])
        #expect(items.allSatisfy { $0.isHeading == false })
        #expect(items.allSatisfy { $0.isCompleted == false })
    }

    @Test func parsesCheckboxSyntax() {
        let items = ShoppingListFreeformConverter.items(from: "- [ ] milk\n- [x] eggs\n- [X] butter")
        #expect(items.map(\.text) == ["milk", "eggs", "butter"])
        #expect(items.map { $0.isCompleted ?? false } == [false, true, true])
    }

    @Test func skipsBlankLinesAndEmptyMarkers() {
        let items = ShoppingListFreeformConverter.items(from: "\n\n#\n* \n  \nmilk")
        #expect(items.count == 1)
        #expect(items[0].text == "milk")
    }

    @Test func emptyTextYieldsNoItems() {
        #expect(ShoppingListFreeformConverter.items(from: "").isEmpty)
    }

    @Test func generatesUniqueIds() {
        let items = ShoppingListFreeformConverter.items(from: "* a\n* b\n* c")
        #expect(Set(items.map(\.id)).count == 3)
    }

    @Test func serializesItemsToText() {
        let items = [
            ShoppingListListContents(id: "h1", isHeading: true, text: "Produce"),
            ShoppingListListContents(id: "i1", text: "apples"),
            ShoppingListListContents(id: "i2", isCompleted: true, text: "bananas"),
        ]
        let text = ShoppingListFreeformConverter.text(from: items)
        #expect(text == "# Produce\n* [ ] apples\n* [x] bananas")
    }

    @Test func serializesEmptyItemsToEmptyString() {
        #expect(ShoppingListFreeformConverter.text(from: []).isEmpty)
    }

    @Test func roundTripsThroughTextPreservingStructureAndCompletion() {
        let original = [
            ShoppingListListContents(id: "h1", isHeading: true, text: "Produce"),
            ShoppingListListContents(id: "i1", isCompleted: false, text: "apples"),
            ShoppingListListContents(id: "i2", isCompleted: true, text: "bananas"),
        ]
        let restored = ShoppingListFreeformConverter.items(from: ShoppingListFreeformConverter.text(from: original))
        #expect(restored.map(\.text) == original.map(\.text))
        #expect(restored.map { $0.isHeading ?? false } == [true, false, false])
        #expect(restored.map { $0.isCompleted ?? false } == [false, false, true])
    }
}

struct ShoppingListSummaryTests {

    private func checklist(_ items: [ShoppingListListContents]) -> ShoppingList {
        ShoppingList(id: "sl", name: "L", isFreeform: false, contentsForList: items)
    }
    private func freeform(_ text: String?) -> ShoppingList {
        ShoppingList(id: "sl", name: "L", isFreeform: true, contentsForFreeform: text)
    }

    @Test func checklistCountsItems() {
        let list = checklist([
            ShoppingListListContents(id: "1", text: "Milk"),
            ShoppingListListContents(id: "2", text: "Eggs"),
        ])
        #expect(list.contentsSummary == "2 items")
    }

    @Test func checklistCountExcludesHeadings() {
        // Headings group items; they aren't things to buy, so they don't count.
        let list = checklist([
            ShoppingListListContents(id: "h", isHeading: true, text: "Produce"),
            ShoppingListListContents(id: "1", text: "Apples"),
        ])
        #expect(list.contentsSummary == "1 item")
    }

    @Test func checklistCountIgnoresCompletion() {
        // The subtitle now reports size, not progress — a ticked item still counts.
        let list = checklist([
            ShoppingListListContents(id: "1", isCompleted: true, text: "Milk"),
            ShoppingListListContents(id: "2", text: "Eggs"),
        ])
        #expect(list.contentsSummary == "2 items")
    }

    @Test func emptyChecklistReadsAsNoItems() {
        #expect(checklist([]).contentsSummary == "No items")
        #expect(checklist([ShoppingListListContents(id: "h", isHeading: true, text: "Produce")]).contentsSummary == "No items")
    }

    @Test func freeformCountsNonBlankLines() {
        // Paragraph spacing in a Markdown document shouldn't inflate the count.
        #expect(freeform("# Store\n\n* Milk\n* Eggs\n").contentsSummary == "3 lines")
    }

    @Test func freeformSingularAndEmpty() {
        #expect(freeform("just one").contentsSummary == "1 line")
        #expect(freeform("").contentsSummary == "Empty")
        #expect(freeform(nil).contentsSummary == "Empty")
        #expect(freeform("\n\n   \n").contentsSummary == "Empty")
    }
}

struct ShoppingListItemsEditingTests {

    private func makeItems() -> [ShoppingListListContents] {
        [
            ShoppingListListContents(id: "h1", isHeading: true, text: "Produce"),
            ShoppingListListContents(id: "i1", text: "apples"),
            ShoppingListListContents(id: "i2", isCompleted: true, text: "bananas"),
            ShoppingListListContents(id: "i3", isImportant: true, text: "carrots"),
        ]
    }

    @Test func toggleCompletedFlipsAndFlipsBack() {
        var items = makeItems()
        items.toggleCompleted(id: "i1")
        #expect(items[1].isCompleted == true)
        items.toggleCompleted(id: "i1")
        #expect(items[1].isCompleted == false)
    }

    @Test func toggleCompletedTreatsNilAsFalse() {
        var items = [ShoppingListListContents(id: "i1", isCompleted: nil, text: "apples")]
        items.toggleCompleted(id: "i1")
        #expect(items[0].isCompleted == true)
    }

    @Test func toggleUnknownIdIsANoOp() {
        var items = makeItems()
        items.toggleCompleted(id: "nope")
        #expect(items == makeItems())
    }

    @Test func toggleImportantFlips() {
        var items = makeItems()
        items.toggleImportant(id: "i3")
        #expect(items[3].isImportant == false)
    }

    @Test func updateTextReplacesOnlyThatItem() {
        var items = makeItems()
        items.updateText(id: "i1", text: "green apples")
        #expect(items[1].text == "green apples")
        #expect(items[2].text == "bananas")
    }

    @Test func clearCompletedRemovesOnlyCompletedItems() {
        var items = makeItems()
        items.clearCompleted()
        #expect(items.map(\.id) == ["h1", "i1", "i3"])
    }

    @Test func uncheckAllKeepsItemsButClearsCompletion() {
        var items = makeItems()
        items.uncheckAll()
        #expect(items.count == 4)
        #expect(items.allSatisfy { !($0.isCompleted ?? false) })
    }

    @Test func insertionIndexAfterItem() {
        let items = makeItems()
        #expect(items.insertionIndex(after: "h1") == 1)
        #expect(items.insertionIndex(after: "i3") == 4)
    }

    @Test func insertionIndexDefaultsToEnd() {
        let items = makeItems()
        #expect(items.insertionIndex(after: nil) == 4)
        #expect(items.insertionIndex(after: "missing") == 4)
    }

    @Test func isBlankTreatsWhitespaceOnlyAsBlank() {
        #expect(ShoppingListListContents(id: "b", text: "").isBlank)
        #expect(ShoppingListListContents(id: "b", text: "   ").isBlank)
        #expect(!ShoppingListListContents(id: "b", text: "milk").isBlank)
    }

    @Test func removeBlankRemovesAnUntypedRow() {
        var items = makeItems()
        items.append(ShoppingListListContents(id: "draft", text: "  "))
        #expect(items.removeBlank(id: "draft") == true)
        #expect(items.map(\.id) == ["h1", "i1", "i2", "i3"])
    }

    @Test func removeBlankLeavesTypedAndUnknownRowsAlone() {
        var items = makeItems()
        #expect(items.removeBlank(id: "i1") == false)
        #expect(items.removeBlank(id: "missing") == false)
        #expect(items == makeItems())
    }

    @Test func removeAllBlankClearsBlankItemsAndHeadings() {
        var items = makeItems()
        items.insert(ShoppingListListContents(id: "b1", isHeading: true, text: ""), at: 0)
        items.append(ShoppingListListContents(id: "b2", text: " "))
        #expect(items.removeAllBlank() == true)
        #expect(items.map(\.id) == ["h1", "i1", "i2", "i3"])
        #expect(items.removeAllBlank() == false)
    }
}
