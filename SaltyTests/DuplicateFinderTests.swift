//
//  DuplicateFinderTests.swift
//  SaltyTests
//
//  The pure halves of the de-duplication feature: which recipes count as copies of each other at each
//  match level (RecipeDuplicateFinder) and which library rows count as identically named, including
//  who survives a merge (LibraryDuplicateFinder). The database side -- actually re-pointing recipes
//  and deleting the merged-away rows -- is covered by DatabaseTests' `DuplicateMerging` suite.
//

import Testing
import Foundation
@testable import Salty

// MARK: - Recipes

struct RecipeDuplicateFinderTests {

    /// A recipe with enough content to make an accidental match unlikely.
    private func makeRecipe(id: String, name: String = "Pancakes", createdDaysAgo: Double = 0) -> Recipe {
        var recipe = Recipe(id: id, name: name)
        recipe.createdDate = Date(timeIntervalSince1970: 1_000_000 - createdDaysAgo * 86_400)
        recipe.lastModifiedDate = recipe.createdDate
        recipe.source = "Grandma"
        recipe.sourceDetails = "Card box, 1974"
        recipe.introduction = "Sunday breakfast."
        recipe.yield = "12 pancakes"
        recipe.servings = 4
        recipe.rating = .four
        recipe.difficulty = .easy
        recipe.ingredients = [
            Ingredient(id: "ing-\(id)-1", isHeading: false, isMain: true, text: "2 cups flour"),
            Ingredient(id: "ing-\(id)-2", isHeading: false, isMain: false, text: "1 1/2 cups milk"),
            Ingredient(id: "ing-\(id)-3", isHeading: false, isMain: false, text: "1/3 cup sugar"),
            Ingredient(id: "ing-\(id)-4", isHeading: false, isMain: false, text: "Salt to taste"),
        ]
        recipe.directions = [Direction(id: "dir-\(id)-1", isHeading: false, text: "Mix and fry.")]
        recipe.notes = [Note(id: "note-\(id)-1", title: "Tip", content: "Rest the batter.")]
        recipe.variations = [Variation(id: "var-\(id)-1", variationName: "Blueberry", text: "Add berries.")]
        recipe.preparationTimes = [PreparationTime(id: "pt-\(id)-1", type: "Cook", timeString: "15 min")]
        recipe.nutrition = NutritionInformation(id: "nut-\(id)", calories: 220, protein: 6)
        return recipe
    }

    /// Reproduces what "duplicate and scale" writes: quantities rebuilt by `IngredientScaler`, a
    /// "Scaled Recipe" note prepended, the percentage appended to the name, and fresh ids throughout.
    private func scaledCopy(of recipe: Recipe, id: String, factor: Double, label: String) -> Recipe {
        var copy = recipe
        copy.id = id
        copy.createdDate = recipe.createdDate.addingTimeInterval(3_600)
        copy.lastModifiedDate = copy.createdDate
        copy.name = "\(recipe.name) (\(label)%)"
        copy.ingredients = recipe.ingredients.enumerated().map { index, ingredient in
            Ingredient(
                id: "ing-\(id)-\(index)",
                isHeading: ingredient.isHeading,
                isMain: ingredient.isMain,
                text: ingredient.isHeading
                    ? ingredient.text
                    : IngredientScaler.scaledText(for: ingredient, scaleFactor: factor)
            )
        }
        copy.notes = [
            Note(
                id: "note-\(id)-scale",
                title: "Scaled Recipe",
                content: "Ingredients scaled to \(label)% from original recipe, “\(recipe.name)”."
            )
        ] + recipe.notes.enumerated().map { index, note in
            Note(id: "note-\(id)-\(index)", title: note.title, content: note.content)
        }
        return copy
    }

    // MARK: All content (strictest)

    @Test func findsCopiesThatDifferOnlyInIdsDatesAndImage() {
        // What "duplicate a recipe" and "import the same file twice" produce: fresh ids at every
        // level, new dates, a separately-stored image.
        var original = makeRecipe(id: "r1", createdDaysAgo: 10)
        original.imageFilename = "r1.jpg"
        original.imageThumbnailData = Data([0x01, 0x02])
        original.lastModifiedImageDate = Date(timeIntervalSince1970: 5)
        var copy = makeRecipe(id: "r2", createdDaysAgo: 0)
        copy.imageFilename = "r2.jpg"
        copy.imageThumbnailData = Data([0x09])
        // Cooking one copy but not the other must not split the group — the prepared date and its sync
        // stamp are bookkeeping, like every other date here.
        copy.lastPrepared = Date(timeIntervalSince1970: 900_000)
        copy.lastModifiedPreparedDate = Date(timeIntervalSince1970: 900_001)

        let groups = RecipeDuplicateFinder.groups(in: [original, copy], level: .allContent)

        #expect(groups.count == 1)
        // Oldest first, so the copy the user most likely wants to keep leads the group.
        #expect(groups.first?.recipes.map(\.id) == ["r1", "r2"])
        #expect(RecipeDuplicateFinder.isDuplicate(original, of: copy, level: .allContent))
    }

    /// The user's own marks drift apart as soon as one copy gets used -- rate one, favorite the other
    /// -- and a copy that stops being reported is the failure that matters here, so these don't count.
    @Test func userSetFlagsDoNotSplitAGroup() {
        var plain = makeRecipe(id: "r1")
        plain.rating = .notSet
        var rated = makeRecipe(id: "r2")
        rated.rating = .two
        var favorited = makeRecipe(id: "r3")
        favorited.isFavorite = true
        favorited.wantToMake = true
        favorited.courseId = "some-course"

        let groups = RecipeDuplicateFinder.groups(in: [plain, rated, favorited], level: .allContent)

        #expect(groups.count == 1)
        #expect(groups.first?.recipes.count == 3)
    }

    /// Formatting a reader can't see must not split a group, at any level: smart quotes, doubled
    /// spaces, a typographic fraction, capitalization, and a stray blank line.
    @Test func allContentIgnoresInvisibleFormattingDifferences() {
        let original = makeRecipe(id: "r1")
        var retyped = makeRecipe(id: "r2")
        retyped.name = "  pancakes "
        retyped.introduction = "Sunday  breakfast."
        retyped.ingredients[1].text = "1½ cups   milk"
        retyped.ingredients.append(Ingredient(id: "ing-blank", isHeading: false, isMain: false, text: "   "))

        #expect(RecipeDuplicateFinder.groups(in: [original, retyped], level: .allContent).count == 1)
    }

    @Test func smartPunctuationMatchesItsPlainEquivalent() {
        var curly = makeRecipe(id: "r1")
        curly.notes[0].content = "Grandma’s batter — rest it 10–15 min…"
        var plain = makeRecipe(id: "r2")
        plain.notes[0].content = "Grandma's batter - rest it 10-15 min..."

        #expect(RecipeDuplicateFinder.isDuplicate(curly, of: plain, level: .allContent))
    }

    @Test func differentIngredientTextIsNotADuplicate() {
        let a = makeRecipe(id: "r1")
        var b = makeRecipe(id: "r2")
        b.ingredients[0].text = "3 cups flour"

        #expect(RecipeDuplicateFinder.groups(in: [a, b], level: .allContent).isEmpty)
        #expect(RecipeDuplicateFinder.groups(in: [a, b]).isEmpty)   // default level compares these too
    }

    // MARK: Ingredients and directions (the default)

    /// The scenario that prompted the levels: duplicate a recipe at 200%, halve that copy back to
    /// 100%, rename it to match. The quantities come back to where they started, but each scaling
    /// adds a "Scaled Recipe" note, so only a level that ignores notes finds the pair.
    @Test func scaledThenUnscaledCopyIsFoundAtTheDefaultLevel() {
        let original = makeRecipe(id: "r1")
        let doubled = scaledCopy(of: original, id: "r2", factor: 2, label: "200")
        var restored = scaledCopy(of: doubled, id: "r3", factor: 0.5, label: "50")
        restored.name = original.name   // the user renames it back by hand

        // The quantities really do round-trip, so this is about the notes, not the arithmetic.
        #expect(restored.ingredients.map(\.text) == original.ingredients.map(\.text))
        #expect(restored.notes.count == original.notes.count + 2)

        #expect(RecipeDuplicateFinder.groups(in: [original, restored], level: .allContent).isEmpty)

        let groups = RecipeDuplicateFinder.groups(in: [original, restored])
        #expect(groups.count == 1)
        #expect(groups.first?.recipes.map(\.id) == ["r1", "r3"])
    }

    @Test func defaultLevelIgnoresEverythingBelowTheIngredients() {
        let original = makeRecipe(id: "r1")
        var edited = makeRecipe(id: "r2")
        edited.introduction = "A different introduction entirely."
        edited.yield = "24 pancakes"
        edited.servings = 8
        edited.difficulty = .difficult
        edited.variations = []
        edited.preparationTimes = []
        edited.nutrition = nil

        #expect(RecipeDuplicateFinder.groups(in: [original, edited]).count == 1)
        // …all of which the strictest level still treats as differences.
        #expect(RecipeDuplicateFinder.groups(in: [original, edited], level: .allContent).isEmpty)
    }

    @Test func defaultLevelIgnoresHeadingAndMainIngredientMarks() {
        let original = makeRecipe(id: "r1")
        var remarked = makeRecipe(id: "r2")
        remarked.ingredients[0].isMain = false
        remarked.directions[0].isHeading = true

        #expect(RecipeDuplicateFinder.groups(in: [original, remarked]).count == 1)
    }

    @Test func defaultLevelStillRequiresTheSameTitleAndSource() {
        let a = makeRecipe(id: "r1")
        var differentName = makeRecipe(id: "r2")
        differentName.name = "Waffles"
        var differentSource = makeRecipe(id: "r3")
        differentSource.source = "A magazine"

        #expect(RecipeDuplicateFinder.groups(in: [a, differentName]).isEmpty)
        #expect(RecipeDuplicateFinder.groups(in: [a, differentSource]).isEmpty)
    }

    // MARK: Title and source (loosest)

    @Test func titleAndSourceGroupsCopiesWhoseContentHasDrifted() {
        let a = makeRecipe(id: "r1")
        var rewritten = makeRecipe(id: "r2")
        rewritten.ingredients = [Ingredient(id: "x", isHeading: false, isMain: true, text: "4 cups flour")]
        rewritten.directions = [Direction(id: "y", isHeading: false, text: "Completely rewritten.")]

        #expect(RecipeDuplicateFinder.groups(in: [a, rewritten]).isEmpty)
        #expect(RecipeDuplicateFinder.groups(in: [a, rewritten], level: .titleAndSource).count == 1)
    }

    @Test func looseLevelsSkipRecipesWithNothingToCompare() {
        // Two blank drafts share an empty title and source; grouping them says nothing useful.
        let blankA = Recipe(id: "r1", name: "")
        let blankB = Recipe(id: "r2", name: "   ")

        #expect(RecipeDuplicateFinder.groups(in: [blankA, blankB], level: .titleAndSource).isEmpty)
        #expect(RecipeDuplicateFinder.groups(in: [blankA, blankB]).isEmpty)
        // At the strictest level they genuinely are identical records, so they're still reported.
        #expect(RecipeDuplicateFinder.groups(in: [blankA, blankB], level: .allContent).count == 1)
    }

    // MARK: Grouping mechanics

    @Test func groupsThreeCopiesTogether() {
        let recipes = [
            makeRecipe(id: "r3", createdDaysAgo: 1),
            makeRecipe(id: "r1", createdDaysAgo: 3),
            makeRecipe(id: "r2", createdDaysAgo: 2),
        ]

        let groups = RecipeDuplicateFinder.groups(in: recipes)

        #expect(groups.count == 1)
        #expect(groups.first?.recipes.map(\.id) == ["r1", "r2", "r3"])
        #expect(groups.first?.id == "r1")
    }

    @Test func ordersGroupsByName() {
        let groups = RecipeDuplicateFinder.groups(in: [
            makeRecipe(id: "z1", name: "Waffles"),
            makeRecipe(id: "z2", name: "Waffles"),
            makeRecipe(id: "a1", name: "Pancakes"),
            makeRecipe(id: "a2", name: "Pancakes"),
        ])

        #expect(groups.map(\.name) == ["Pancakes", "Waffles"])
    }

    @Test func emptyLibraryHasNoDuplicates() {
        for level in RecipeDuplicateMatchLevel.allCases {
            #expect(RecipeDuplicateFinder.groups(in: [], level: level).isEmpty)
            #expect(RecipeDuplicateFinder.groups(in: [makeRecipe(id: "r1")], level: level).isEmpty)
        }
    }

    // MARK: Text normalization

    @Test func normalizesCaseWhitespaceAndPunctuation() {
        #expect(RecipeDuplicateFinder.normalizedText("  Mix   WELL\n") == "mix well")
        #expect(RecipeDuplicateFinder.normalizedText("Grandma’s") == "grandma's")
        #expect(RecipeDuplicateFinder.normalizedText("“quoted”") == "\"quoted\"")
        #expect(RecipeDuplicateFinder.normalizedText("10–15 min") == "10-15 min")
        #expect(RecipeDuplicateFinder.normalizedText("1\u{00A0}cup") == "1 cup")
        #expect(RecipeDuplicateFinder.normalizedText("   ").isEmpty)
    }

    @Test func normalizesTypographicFractions() {
        // The glyph gets a leading space so "1½" reads as "1 1/2", not "11/2".
        #expect(RecipeDuplicateFinder.normalizedText("1½ cups") == "1 1/2 cups")
        #expect(RecipeDuplicateFinder.normalizedText("½ cup") == "1/2 cup")
        #expect(RecipeDuplicateFinder.normalizedText("⅓ cup") == "1/3 cup")
        #expect(RecipeDuplicateFinder.normalizedText("¾ tsp") == "3/4 tsp")
    }

    @Test func normalizesCombiningAccentsToPrecomposed() {
        let combining = "cre\u{0301}me"      // e + combining acute
        let precomposed = "cr\u{00E9}me"     // é as a single scalar
        #expect(RecipeDuplicateFinder.normalizedText(combining) == RecipeDuplicateFinder.normalizedText(precomposed))
    }
}

// MARK: - Categories / courses / tags

struct LibraryDuplicateFinderTests {

    @Test func groupsNamesIgnoringCaseAndSurroundingWhitespace() {
        let groups = LibraryDuplicateFinder.groups(kind: .category, items: [
            LibraryDuplicateItem(id: "c1", name: "Breads", recipeCount: 4),
            LibraryDuplicateItem(id: "c2", name: " breads ", recipeCount: 1),
            LibraryDuplicateItem(id: "c3", name: "Soups", recipeCount: 2),
        ])

        #expect(groups.count == 1)
        #expect(groups.first?.survivor.id == "c1")
        #expect(groups.first?.duplicates.map(\.id) == ["c2"])
    }

    @Test func collapsesInternalWhitespace() {
        let groups = LibraryDuplicateFinder.groups(kind: .course, items: [
            LibraryDuplicateItem(id: "co1", name: "Side Dish", recipeCount: 3),
            LibraryDuplicateItem(id: "co2", name: "Side  dish", recipeCount: 1),
        ])

        #expect(groups.count == 1)
        #expect(groups.first?.removedCount == 1)
    }

    @Test func survivorIsTheMostUsedRow() {
        let groups = LibraryDuplicateFinder.groups(kind: .tag, items: [
            LibraryDuplicateItem(id: "t9", name: "vegan", recipeCount: 1),
            LibraryDuplicateItem(id: "t1", name: "Vegan", recipeCount: 7),
            LibraryDuplicateItem(id: "t5", name: "VEGAN", recipeCount: 3),
        ])

        #expect(groups.first?.survivor.id == "t1")
        // Its exact spelling is what remains.
        #expect(groups.first?.name == "Vegan")
        #expect(groups.first?.duplicates.map(\.id) == ["t5", "t9"])
    }

    @Test func tiesGoToTheOldestRow() {
        // UUIDv7 ids sort by creation time, so the smallest id is the earliest-created row.
        let groups = LibraryDuplicateFinder.groups(kind: .tag, items: [
            LibraryDuplicateItem(id: "b-newer", name: "quick", recipeCount: 2),
            LibraryDuplicateItem(id: "a-older", name: "Quick", recipeCount: 2),
        ])

        #expect(groups.first?.survivor.id == "a-older")
    }

    @Test func skipsBlankNames() {
        // Two unnamed rows aren't evidence of the same thing; merging them would be a guess.
        let groups = LibraryDuplicateFinder.groups(kind: .category, items: [
            LibraryDuplicateItem(id: "c1", name: "", recipeCount: 1),
            LibraryDuplicateItem(id: "c2", name: "   ", recipeCount: 2),
        ])

        #expect(groups.isEmpty)
    }

    @Test func uniqueNamesProduceNoGroups() {
        let groups = LibraryDuplicateFinder.groups(kind: .category, items: [
            LibraryDuplicateItem(id: "c1", name: "Breads", recipeCount: 1),
            LibraryDuplicateItem(id: "c2", name: "Soups", recipeCount: 1),
        ])

        #expect(groups.isEmpty)
    }

    @Test func normalizationIsStable() {
        #expect(LibraryDuplicateFinder.normalizedName("  Main   Dish  ") == "main dish")
        #expect(LibraryDuplicateFinder.normalizedName("\tSNACK\n") == "snack")
        #expect(LibraryDuplicateFinder.normalizedName("   ").isEmpty)
    }
}
