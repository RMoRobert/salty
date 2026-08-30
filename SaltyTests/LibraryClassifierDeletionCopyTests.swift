//
//  LibraryClassifierDeletionCopyTests.swift
//  SaltyTests
//
//  What the classifier editor's delete confirmation has to tell the user -- deliberately not how it
//  phrases it. The count is the whole point: it's the difference between "Delete Desserts?" and
//  knowing that 30 recipes are about to lose it.
//
//  Assertions are substring and relationship checks so the wording can be rewritten freely. The two
//  places that still lean on specific words are `hedge` and `recipeWord` below -- reword the sentence
//  however you like and update those two constants, and the rest of the file keeps working.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

@MainActor
struct LibraryClassifierDeletionCopyTests {

    /// The words carrying "this total may double-count". Reword freely, but keep saying it somehow:
    /// whether a count is exact or an upper bound is a fact about the data, not a turn of phrase.
    private let hedge = "up to"

    /// The noun the counts are given in, for the singular/plural checks.
    private let recipeWord = "recipe"

    private func item(_ name: String, used: Int) -> LibraryClassifierItem {
        LibraryClassifierItem(id: name.lowercased(), name: name, recipeCount: used)
    }

    private func title(_ rows: [LibraryClassifierItem], _ classifier: LibraryClassifier) -> String {
        LibraryClassifiersEditViewModel.deletionTitle(for: rows, classifier: classifier)
    }

    private func message(_ rows: [LibraryClassifierItem], _ classifier: LibraryClassifier) -> String {
        LibraryClassifiersEditViewModel.deletionMessage(for: rows, classifier: classifier)
    }

    /// Wrapped rather than inlined: `contains(where:)` is `rethrows`, which `#expect` won't take.
    private func hasADigit(_ text: String) -> Bool {
        text.contains(where: \.isNumber)
    }

    // MARK: - Title

    @Test func aSingleRowIsNamedInTheTitle() {
        #expect(title([item("Desserts", used: 4)], .category).contains("Desserts"))
    }

    /// Several rows can't all be named in a title, so it counts them instead -- and naming just one of
    /// them would be worse than naming none.
    @Test func severalRowsAreCountedRatherThanNamed() {
        let rows = [item("Breads", used: 1), item("Soups", used: 2), item("Salads", used: 0)]
        let text = title(rows, .category)
        #expect(text.contains("3"))
        for name in ["Breads", "Soups", "Salads"] {
            #expect(!text.contains(name))
        }
    }

    // MARK: - Message: the count

    /// Nothing is using it, so there is no count to give -- and no number should appear at all, since
    /// any number here would read as a number of recipes.
    @Test func anUnusedRowClaimsNoRecipeCount() {
        let text = message([item("Grill", used: 0)], .tag)
        #expect(!text.isEmpty)
        #expect(!hasADigit(text))
    }

    @Test func theCountIsSingularForOneRecipe() {
        let text = message([item("Grill", used: 1)], .tag)
        #expect(text.contains("1 \(recipeWord)"))
        #expect(!text.contains("1 \(recipeWord)s"))
    }

    @Test func countsAcrossSeveralRowsAreSummed() {
        #expect(message([item("Grill", used: 2), item("Freezer", used: 3)], .tag).contains("5"))
    }

    /// A recipe can carry two of the categories/tags being deleted at once, so a multi-row total is an
    /// upper bound and has to say so.
    @Test func multiRowCategoryAndTagTotalsAreHedged() {
        #expect(message([item("Grill", used: 2), item("Freezer", used: 3)], .tag).contains(hedge))
        #expect(message([item("Breads", used: 1), item("Soups", used: 2)], .category).contains(hedge))
    }

    /// One row has nothing to double-count, and neither do courses -- a recipe holds only one. Both
    /// totals are exact, so hedging them would understate what the delete costs.
    @Test func exactTotalsAreNotHedged() {
        #expect(!message([item("Grill", used: 4)], .tag).contains(hedge))
        #expect(!message([item("Dessert", used: 2), item("Main Dish", used: 3)], .course).contains(hedge))
    }

    // MARK: - Message: what actually happens

    /// Deleting a category or tag leaves the recipe; deleting a course clears the recipe's one course
    /// slot. Different outcomes, so they can't share a sentence.
    @Test func coursesAreDescribedDifferentlyFromCategoriesAndTags() {
        let rows = [item("Dessert", used: 4)]
        #expect(message(rows, .course) != message(rows, .category))
        #expect(message(rows, .course) != message(rows, .tag))
    }

    @Test func severalRowsAreDescribedInThePlural() {
        let rows = [item("Breads", used: 1), item("Soups", used: 2)]
        let text = message(rows, .category)
        #expect(text.localizedCaseInsensitiveContains(LibraryClassifier.category.pluralLabel))
        #expect(text != message([item("Breads", used: 3)], .category))
    }

    /// One editor serves all three, so the risk is a tag delete warning about categories. Nothing is
    /// required to *name* the classifier -- only to never name one of the others.
    @Test func theMessageNeverNamesAnotherClassifier() {
        for classifier in LibraryClassifier.allCases {
            let text = message([item("Zzz", used: 4)], classifier)
            for other in LibraryClassifier.allCases where other != classifier {
                #expect(
                    !text.localizedCaseInsensitiveContains(other.singularLabel),
                    "a \(classifier.rawValue) delete mentioned \(other.singularLabel): \(text)"
                )
            }
        }
    }

    /// The count noun is written once. An interpolated "4 recipes" plus a literal "recipe(s)" was
    /// rendering as "4 recipes recipe(s)"; a raw enum interpolation leaked "LibraryClassifier".
    @Test func nothingIsDoubledUpOrLeakedFromTheCode() {
        for classifier in LibraryClassifier.allCases {
            let text = message([item("Zzz", used: 4)], classifier)
            #expect(!text.contains("\(recipeWord)(s)"))
            #expect(!text.contains("\(recipeWord)s \(recipeWord)"))
            #expect(!text.contains("LibraryClassifier"))
            #expect(!text.contains("Optional("))
        }
    }
}
