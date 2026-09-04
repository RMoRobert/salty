//
//  RecipeItemListEditorTests.swift
//  SaltyTests
//
//  Covers the add / insert / delete / reorder logic behind the ingredient and direction editors --
//  logic that used to live inline in two views and so couldn't be tested at all.
//
//  The reordering cases are the point of the exercise: the drop handler these replace worked from
//  the dragged row's *index*, encoded into the drag payload, and adjusted it by hand at the drop
//  site. Everything here is addressed by id, so a stale or foreign payload is refused rather than
//  applied to whichever row happens to sit at that index now.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

/// Ingredients named after their position, so a reordered list reads as its expected order.
private func ingredients(_ names: String...) -> [Ingredient] {
    names.map { Ingredient(id: $0, isHeading: false, isMain: false, text: $0) }
}

private func names(_ items: [Ingredient]) -> [String] {
    items.map(\.id)
}

@Suite struct RecipeItemListEditorTests {

    // MARK: - Inserting

    @Test func insertPutsTheNewRowDirectlyBelowTheOneItWasAddedFrom() {
        var items = ingredients("a", "b", "c")

        let newID = RecipeItemListEditor.insert(.emptyRow(isHeading: false), below: "a", in: &items)

        #expect(names(items) == ["a", newID, "b", "c"])
    }

    @Test func insertBelowTheLastRowAppends() {
        var items = ingredients("a", "b")

        let newID = RecipeItemListEditor.insert(.emptyRow(isHeading: false), below: "b", in: &items)

        #expect(names(items) == ["a", "b", newID])
    }

    /// The "add" button on a row can outlive the row itself if a delete lands first; the new row
    /// still has to go somewhere.
    @Test func insertBelowAMissingRowAppendsRatherThanDroppingTheRow() {
        var items = ingredients("a", "b")

        let newID = RecipeItemListEditor.insert(.emptyRow(isHeading: false), below: "gone", in: &items)

        #expect(names(items) == ["a", "b", newID])
    }

    @Test func appendReturnsTheNewRowsIDSoTheViewCanFocusIt() {
        var items = ingredients("a")

        let newID = RecipeItemListEditor.append(.emptyRow(isHeading: true), to: &items)

        #expect(names(items) == ["a", newID])
        #expect(items.last?.isHeadingRow == true)
    }

    @Test func newMainIngredientIsNeverAlsoAHeading() {
        let main = Ingredient.emptyRow(isHeading: true, isMain: true)

        #expect(main.isMain)
        #expect(!main.isHeadingRow)
    }

    // MARK: - Deleting

    @Test func deleteRemovesOnlyTheNamedRow() {
        var items = ingredients("a", "b", "c")

        #expect(RecipeItemListEditor.delete(id: "b", from: &items))
        #expect(names(items) == ["a", "c"])
    }

    @Test func deletingARowThatIsAlreadyGoneIsRefusedRatherThanRemovingSomethingElse() {
        var items = ingredients("a", "b")

        #expect(!RecipeItemListEditor.delete(id: "gone", from: &items))
        #expect(names(items) == ["a", "b"])
    }

    // MARK: - Reordering

    @Test func movingARowUpwardsLandsItAboveTheTarget() {
        var items = ingredients("a", "b", "c", "d")

        #expect(RecipeItemListEditor.move(id: "d", to: .above("b"), in: &items))
        #expect(names(items) == ["a", "d", "b", "c"])
    }

    /// The old handler pushed a downward drag *past* its target -- a row dropped on "c" landed after
    /// it. Dropping now always means "above the row the indicator is drawn on", either direction.
    @Test func movingARowDownwardsAlsoLandsItAboveTheTarget() {
        var items = ingredients("a", "b", "c", "d")

        #expect(RecipeItemListEditor.move(id: "a", to: .above("c"), in: &items))
        #expect(names(items) == ["b", "a", "c", "d"])
    }

    @Test func movingToTheEndPutsTheRowLast() {
        var items = ingredients("a", "b", "c")

        #expect(RecipeItemListEditor.move(id: "a", to: .end, in: &items))
        #expect(names(items) == ["b", "c", "a"])
    }

    @Test func droppingARowOnItselfChangesNothing() {
        var items = ingredients("a", "b", "c")

        #expect(!RecipeItemListEditor.move(id: "b", to: .above("b"), in: &items))
        #expect(names(items) == ["a", "b", "c"])
    }

    @Test func droppingARowJustBelowWhereItAlreadySitsChangesNothing() {
        var items = ingredients("a", "b", "c")

        #expect(!RecipeItemListEditor.move(id: "a", to: .above("b"), in: &items))
        #expect(names(items) == ["a", "b", "c"])
    }

    @Test func droppingTheLastRowOnTheEndZoneChangesNothing() {
        var items = ingredients("a", "b", "c")

        #expect(!RecipeItemListEditor.move(id: "c", to: .end, in: &items))
        #expect(names(items) == ["a", "b", "c"])
    }

    /// A plain-text drag from anywhere else on the system arrives as a String just like a row id
    /// does. Matching the payload against the list is what tells them apart.
    @Test func aPayloadThatIsNotARowInThisListIsRefused() {
        var items = ingredients("a", "b", "c")

        #expect(!RecipeItemListEditor.move(id: "some dragged text", to: .above("b"), in: &items))
        #expect(names(items) == ["a", "b", "c"])
    }

    @Test func aTargetRowDeletedMidDragIsRefused() {
        var items = ingredients("a", "b", "c")

        #expect(!RecipeItemListEditor.move(id: "a", to: .above("gone"), in: &items))
        #expect(names(items) == ["a", "b", "c"])
    }

    @Test func movingWorksOnDirectionsToo() {
        var items = [
            Direction(id: "one", isHeading: false, text: "Chop"),
            Direction(id: "two", isHeading: false, text: "Fry"),
        ]

        #expect(RecipeItemListEditor.move(id: "two", to: .above("one"), in: &items))
        #expect(items.map(\.id) == ["two", "one"])
    }

    // MARK: - Step numbers

    @Test func stepNumbersSkipHeadingsRatherThanCountingThem() {
        let directions = [
            Direction(id: "h1", isHeading: true, text: "For the sauce"),
            Direction(id: "s1", isHeading: false, text: "Chop"),
            Direction(id: "h2", isHeading: true, text: "To assemble"),
            Direction(id: "s2", isHeading: false, text: "Stir"),
        ]

        #expect(RecipeItemListEditor.stepNumber(forDirectionWith: "s1", in: directions) == 1)
        #expect(RecipeItemListEditor.stepNumber(forDirectionWith: "s2", in: directions) == 2)
    }

    @Test func headingsHaveNoStepNumber() {
        let directions = [
            Direction(id: "s1", isHeading: false, text: "Chop"),
            Direction(id: "h1", isHeading: true, text: "To finish"),
        ]

        #expect(RecipeItemListEditor.stepNumber(forDirectionWith: "h1", in: directions) == nil)
    }

    /// Older recipes leave `isHeading` unset rather than false.
    @Test func aDirectionWithNoHeadingFlagIsAnOrdinaryStep() {
        let directions = [Direction(id: "s1", text: "Chop")]

        #expect(RecipeItemListEditor.stepNumber(forDirectionWith: "s1", in: directions) == 1)
    }

    @Test func aDirectionThatIsNoLongerInTheListHasNoStepNumber() {
        let directions = [Direction(id: "s1", isHeading: false, text: "Chop")]

        #expect(RecipeItemListEditor.stepNumber(forDirectionWith: "gone", in: directions) == nil)
    }

    // MARK: - Striping

    @Test func shortListsAreNotStriped() {
        let items = ingredients("a", "b")

        #expect(!RecipeItemListEditor.isAlternateRow(id: "b", in: items))
    }

    @Test func longerListsTintEveryOtherRow() {
        let items = ingredients("a", "b", "c", "d")

        #expect(!RecipeItemListEditor.isAlternateRow(id: "a", in: items))
        #expect(RecipeItemListEditor.isAlternateRow(id: "b", in: items))
        #expect(!RecipeItemListEditor.isAlternateRow(id: "c", in: items))
        #expect(RecipeItemListEditor.isAlternateRow(id: "d", in: items))
    }
}
