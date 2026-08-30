//
//  LibraryClassifierMergeCopyTests.swift
//  SaltyTests
//
//  What the classifier editor's merge sheet has to tell the user -- deliberately not how it phrases
//  it. The assertions are substring and relationship checks, so the wording can be rewritten freely
//  without touching this file.
//
//  What they do guard is the part a merge can't be undone from: that the sentence names the row being
//  kept and not some other row, that it follows the picker rather than a fixed choice, and that it
//  says nothing about a merge when no survivor has been chosen yet.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

@MainActor
struct LibraryClassifierMergeCopyTests {

    private func item(_ id: String, _ name: String, used: Int) -> LibraryClassifierItem {
        LibraryClassifierItem(id: id, name: name, recipeCount: used)
    }

    private func title(_ rows: [LibraryClassifierItem], _ classifier: LibraryClassifier) -> String {
        LibraryClassifiersEditViewModel.mergeTitle(for: rows, classifier: classifier)
    }

    private func message(
        _ rows: [LibraryClassifierItem],
        keeping survivorID: String?,
        _ classifier: LibraryClassifier
    ) -> String {
        LibraryClassifiersEditViewModel.mergeMessage(for: rows, survivorID: survivorID, classifier: classifier)
    }

    /// Two rows that mean the same thing, spelled differently -- the case the picker exists for.
    private var desserts: [LibraryClassifierItem] {
        [item("1", "Desserts", used: 12), item("2", "Deserts", used: 3)]
    }

    /// More rows than the sentence names individually, so only the survivor is left named.
    private var manyRows: [LibraryClassifierItem] {
        [item("1", "Desserts", used: 12)] + (2...6).map { item("\($0)", "Extra \($0)", used: 1) }
    }

    // MARK: - Title

    /// One editor serves all three classifiers, so the risk here is a tag merge announcing itself as
    /// a category one.
    @Test func titleNamesTheClassifierBeingMerged() {
        #expect(title(desserts, .category).contains("Categories"))
        #expect(title(manyRows, .tag).contains("Tags"))
        #expect(!title(desserts, .category).contains("Tag"))
    }

    // MARK: - Message

    @Test func everyRowInASmallMergeIsNamed() {
        let rows = desserts + [item("3", "Puddings", used: 1)]
        let text = message(rows, keeping: "1", .category)
        for name in ["Desserts", "Deserts", "Puddings"] {
            #expect(text.contains(name))
        }
    }

    /// The one thing the sentence must get right: the name that stays is the one that was picked.
    ///
    /// Checked on a merge big enough that the rows being folded away are summarized rather than
    /// listed, so the only name left in the sentence is the survivor's -- which makes this hold
    /// whatever the surrounding words are.
    @Test func onlyTheChosenSurvivorIsNamedInALargeMerge() {
        let keepingDesserts = message(manyRows, keeping: "1", .category)
        #expect(keepingDesserts.contains("Desserts"))
        #expect(!keepingDesserts.contains("Extra"))

        // Same rows, different pick: the naming has to follow it.
        let keepingExtra = message(manyRows, keeping: "3", .category)
        #expect(keepingExtra.contains("Extra 3"))
        #expect(!keepingExtra.contains("Desserts"))
    }

    /// Past a handful the sentence stops listing and starts counting -- the rows are all on screen
    /// above it either way.
    @Test func largeMergesCountTheRowsInsteadOfNamingThem() {
        let text = message(manyRows, keeping: "1", .category)
        #expect(text.contains("5"))
    }

    /// A recipe holds one course, so merging courses replaces a recipe's course rather than adding
    /// to a set -- a real difference in what happens, which the sentence shouldn't paper over.
    @Test func courseMergesAreDescribedDifferentlyFromCategoryMerges() {
        let rows = [item("1", "Main Dish", used: 30), item("2", "Entrees", used: 4)]
        #expect(message(rows, keeping: "1", .course) != message(rows, keeping: "1", .category))
    }

    // MARK: - Nothing to describe

    /// No survivor picked yet: with nothing chosen the sentence can't say what happens to whom, so it
    /// must not name the rows at all rather than guess at one.
    @Test func withoutASurvivorNoRowIsNamed() {
        let text = message(desserts, keeping: nil, .category)
        #expect(!text.isEmpty)
        #expect(!text.contains("Desserts"))
        #expect(!text.contains("Deserts"))
    }

    /// Same when the survivor id belongs to a row that is no longer in the list.
    @Test func aSurvivorThatIsGoneNamesNoRow() {
        let text = message(desserts, keeping: "gone", .tag)
        #expect(!text.isEmpty)
        #expect(!text.contains("Desserts"))
    }

    /// A single row has nothing to merge into it. The guard that actually prevents this reaching the
    /// database is in `confirmMerge`; this only checks the sheet doesn't announce a merge anyway.
    @Test func aLoneRowIsNotDescribedAsAMerge() {
        let rows = [item("1", "Desserts", used: 12)]
        let text = message(rows, keeping: "1", .category)
        #expect(!text.isEmpty)
        #expect(text != message(desserts, keeping: "1", .category))
    }
}
