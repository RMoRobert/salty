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
import SwiftUI
@testable import Salty
import SaltyCore

/// Stands in for the view state a row's binding writes back into, so the binding tests can mutate
/// the list out from under a binding the way a delete or a drag does.
@MainActor
private final class Storage {
    var items: [Ingredient]

    init(_ items: [Ingredient]) {
        self.items = items
    }

    var binding: Binding<[Ingredient]> {
        Binding(get: { self.items }, set: { self.items = $0 })
    }
}

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

    // MARK: - Keyboard reordering

    @Test func moveUpSwapsTheRowWithTheOneAboveIt() {
        var items = ingredients("a", "b", "c")

        #expect(RecipeItemListEditor.moveUp(id: "b", in: &items))
        #expect(names(items) == ["b", "a", "c"])
    }

    @Test func moveDownSwapsTheRowWithTheOneBelowIt() {
        var items = ingredients("a", "b", "c")

        #expect(RecipeItemListEditor.moveDown(id: "b", in: &items))
        #expect(names(items) == ["a", "c", "b"])
    }

    @Test func repeatedMoveDownWalksARowToTheEnd() {
        var items = ingredients("a", "b", "c")

        #expect(RecipeItemListEditor.moveDown(id: "a", in: &items))
        #expect(RecipeItemListEditor.moveDown(id: "a", in: &items))
        #expect(names(items) == ["b", "c", "a"])
    }

    /// The false return is what lets the key press fall through instead of being swallowed at the
    /// ends of the list.
    @Test func theFirstRowCannotMoveUp() {
        var items = ingredients("a", "b")

        #expect(!RecipeItemListEditor.moveUp(id: "a", in: &items))
        #expect(names(items) == ["a", "b"])
    }

    @Test func theLastRowCannotMoveDown() {
        var items = ingredients("a", "b")

        #expect(!RecipeItemListEditor.moveDown(id: "b", in: &items))
        #expect(names(items) == ["a", "b"])
    }

    @Test func movingARowThatIsNotInTheListDoesNothing() {
        var items = ingredients("a", "b")

        #expect(!RecipeItemListEditor.moveUp(id: "gone", in: &items))
        #expect(!RecipeItemListEditor.moveDown(id: "gone", in: &items))
        #expect(names(items) == ["a", "b"])
    }

    @Test func theOnlyRowCannotMoveEitherWay() {
        var items = ingredients("a")

        #expect(!RecipeItemListEditor.moveUp(id: "a", in: &items))
        #expect(!RecipeItemListEditor.moveDown(id: "a", in: &items))
    }

    // MARK: - Row bindings

    /// The crash this guards against: a row outlives its own deletion for the length of the removal
    /// animation, and a position-based binding reads past the end of the array when that row was the
    /// last one -- which a just-added row always is.
    @MainActor
    @Test func aRowsBindingSurvivesThatRowBeingDeleted() {
        let storage = Storage(ingredients("a", "b", "c"))
        let last = storage.items[2]
        let binding = RecipeItemListEditor.binding(for: "c", in: storage.binding, fallback: last)

        storage.items.removeLast()

        #expect(binding.wrappedValue == last)
    }

    @MainActor
    @Test func writingThroughADeletedRowsBindingDoesNotLandOnAnotherRow() {
        let storage = Storage(ingredients("a", "b", "c"))
        let last = storage.items[2]
        let binding = RecipeItemListEditor.binding(for: "c", in: storage.binding, fallback: last)

        storage.items.removeLast()
        binding.wrappedValue.text = "typed after the row was gone"

        #expect(storage.items.map(\.text) == ["a", "b"])
    }

    @MainActor
    @Test func aRowsBindingFollowsThatRowWhenTheListIsReordered() {
        let storage = Storage(ingredients("a", "b", "c"))
        let binding = RecipeItemListEditor.binding(for: "a", in: storage.binding, fallback: storage.items[0])

        RecipeItemListEditor.moveDown(id: "a", in: &storage.items)
        binding.wrappedValue.text = "still a"

        #expect(storage.items.map(\.id) == ["b", "a", "c"])
        #expect(storage.items[1].text == "still a")
    }

    // MARK: - The other recipe lists

    @Test func theSameEditorDrivesNotesPreparationTimesAndVariations() {
        var notes = [Note(id: "n1", title: "One", content: ""), Note(id: "n2", title: "Two", content: "")]
        #expect(RecipeItemListEditor.moveDown(id: "n1", in: &notes))
        #expect(notes.map(\.id) == ["n2", "n1"])

        var times = [
            PreparationTime(id: "t1", type: "Prep", timeString: "10 min"),
            PreparationTime(id: "t2", type: "Bake", timeString: "1 hr"),
        ]
        #expect(RecipeItemListEditor.move(id: "t2", to: .above("t1"), in: &times))
        #expect(times.map(\.id) == ["t2", "t1"])

        var variations = [Variation(id: "v1", variationName: "Spicy", text: "")]
        let newID = RecipeItemListEditor.insert(.emptyRow(), below: "v1", in: &variations)
        #expect(variations.map(\.id) == ["v1", newID])
        #expect(RecipeItemListEditor.delete(id: "v1", from: &variations))
        #expect(variations.map(\.id) == [newID])
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
