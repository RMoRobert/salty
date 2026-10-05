//
//  RecipeClassificationDraftTests.swift
//  SaltyTests
//
//  The recipe editor's held categories and tags. The rules that matter: a typed tag name that the
//  library already has (by the library's duplicate rule) selects that tag rather than queuing a
//  second copy, a name it doesn't have is queued once, and removing by the shown name works for both.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

@Suite("RecipeClassificationDraft")
struct RecipeClassificationDraftTests {
    private let library = [
        Tag(id: "t-quick", name: "Quick"),
        Tag(id: "t-weeknight", name: "Weeknight  Dinner"),
    ]

    @Test func aNameTheLibraryHasSelectsThatTagWhateverItsCaseOrSpacing() {
        var draft = RecipeClassificationDraft()

        let addedQuick = draft.addTag(named: "  quick ", library: library)
        let addedWeeknight = draft.addTag(named: "weeknight dinner", library: library)
        #expect(addedQuick && addedWeeknight)

        #expect(draft.tagIDs == ["t-quick", "t-weeknight"])
        #expect(draft.newTagNames.isEmpty)
        #expect(draft.tagNames(in: library) == ["Quick", "Weeknight  Dinner"], "shown with the library's spelling")
    }

    @Test func anUnknownNameIsQueuedOnceTrimmed() {
        var draft = RecipeClassificationDraft()

        let added = draft.addTag(named: " Spicy ", library: library)
        let addedAgain = draft.addTag(named: "spicy", library: library)
        let addedBlank = draft.addTag(named: "   ", library: library)
        #expect(added)
        #expect(!addedAgain, "the same name again is not a second tag")
        #expect(!addedBlank)

        #expect(draft.newTagNames == ["Spicy"])
        #expect(draft.tagNames(in: library) == ["Spicy"])
    }

    @Test func aTagAlreadyCarriedIsNotAddedAgain() {
        var draft = RecipeClassificationDraft(tagIDs: ["t-quick"])
        let added = draft.addTag(named: "Quick", library: library)
        #expect(!added)
        #expect(draft.tagIDs == ["t-quick"])
    }

    @Test func removingByTheShownNameWorksForLibraryAndQueuedTags() {
        var draft = RecipeClassificationDraft(tagIDs: ["t-quick"], newTagNames: ["Spicy"])

        let removedQuick = draft.removeTag(named: "Quick", library: library)
        let removedSpicy = draft.removeTag(named: "spicy", library: library)
        let removedNothing = draft.removeTag(named: "Nothing", library: library)
        #expect(removedQuick && removedSpicy)
        #expect(!removedNothing)

        #expect(draft.tagIDs.isEmpty)
        #expect(draft.newTagNames.isEmpty)
    }

    @Test func namesAreSortedTogetherAndDeletedTagsShowNothing() {
        let draft = RecipeClassificationDraft(tagIDs: ["t-weeknight", "t-gone"], newTagNames: ["Baking"])
        #expect(draft.tagNames(in: library) == ["Baking", "Weeknight  Dinner"])

        let categories = [Category(id: "c-b", name: "bread"), Category(id: "c-a", name: "Appetizers")]
        let filed = RecipeClassificationDraft(categoryIDs: ["c-a", "c-b"])
        #expect(filed.categoryNames(in: categories) == ["Appetizers", "bread"])
    }

    @Test func equalityIsWhatTheEditorMeansByChanged() {
        let original = RecipeClassificationDraft(categoryIDs: ["c-a"], tagIDs: ["t-quick"])
        var edited = original
        #expect(edited == original)

        edited.addTag(named: "Spicy", library: library)
        #expect(edited != original)
        edited.removeTag(named: "Spicy", library: library)
        #expect(edited == original, "adding and removing a queued tag leaves no trace")
    }
}
