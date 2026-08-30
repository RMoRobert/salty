//
//  RecipeDuplicateFinder.swift
//  Salty
//
//  Finds recipes that are copies of each other -- the "Show Duplicate Recipes" command. Purely a
//  reporting tool: nothing here mutates the database, the user decides what (if anything) to delete.
//
//  Kept free of database and view state so it can be unit-tested against plain `Recipe` values
//  (see RecipeDuplicateFinderTests).
//

import Foundation

/// A set of two or more recipes that matched at the current strictness level.
public struct RecipeDuplicateGroup: Identifiable, Equatable, Sendable {
    /// The recipes in the group, oldest first (created date, then id, so the order is stable).
    public let recipes: [Recipe]

    /// Stable identity for `ForEach`: the id of the group's first (oldest) recipe.
    public var id: String { recipes.first?.id ?? "" }

    /// The heading for the group. The oldest copy's name -- at looser levels the names are equal
    /// apart from capitalization and spacing, so any member would read the same.
    public var name: String { recipes.first?.name ?? "" }

    public init(recipes: [Recipe]) {
        self.recipes = recipes
    }
}

public enum RecipeDuplicateFinder {

    /// Groups `recipes` at the given strictness, returning only the groups with more than one member.
    ///
    /// Groups are ordered by name (localized, case-insensitive), then by id for stability.
    public static func groups(
        in recipes: [Recipe],
        level: RecipeDuplicateMatchLevel = .defaultLevel
    ) -> [RecipeDuplicateGroup] {
        var buckets: [MatchKey: [Recipe]] = [:]
        for recipe in recipes {
            let key = matchKey(for: recipe, level: level)
            // A recipe with nothing to compare (a blank draft matched on title and source) would
            // otherwise pull every other blank recipe into one meaningless group.
            guard !key.isEmpty else { continue }
            buckets[key, default: []].append(recipe)
        }

        return buckets.values
            .filter { $0.count > 1 }
            .map { group in
                RecipeDuplicateGroup(
                    recipes: group.sorted {
                        $0.createdDate == $1.createdDate ? $0.id < $1.id : $0.createdDate < $1.createdDate
                    }
                )
            }
            .sorted {
                let byName = $0.name.localizedStandardCompare($1.name)
                return byName == .orderedSame ? $0.id < $1.id : byName == .orderedAscending
            }
    }

    /// Whether two recipes count as copies of each other at the given strictness.
    public static func isDuplicate(
        _ lhs: Recipe,
        of rhs: Recipe,
        level: RecipeDuplicateMatchLevel = .defaultLevel
    ) -> Bool {
        matchKey(for: lhs, level: level) == matchKey(for: rhs, level: level)
    }

    // MARK: - Match keys

    /// What two recipes are compared on. Two recipes are copies exactly when their keys are equal.
    public enum MatchKey: Hashable {
        /// The looser levels: a fixed set of fields, each already normalized.
        case fields(FieldKey)
        /// `.allContent`: the whole record, with the excluded columns blanked (see `normalized(_:)`).
        case wholeRecipe(Recipe)

        public var isEmpty: Bool {
            switch self {
            case .fields(let key): return key.isEmpty
            // An entirely blank recipe still has a meaningful "everything matches" answer, and two of
            // them really are copies, so nothing is skipped at this level.
            case .wholeRecipe: return false
            }
        }
    }

    /// The normalized fields the looser levels compare. `nil` lists mean "this level doesn't look at
    /// them", which is distinct from an empty list ("this level looks, and there are none").
    public struct FieldKey: Hashable {
        public var name: String
        public var source: String
        public var sourceDetails: String
        public var ingredients: [String]?
        public var directions: [String]?

        public var isEmpty: Bool {
            name.isEmpty && source.isEmpty && sourceDetails.isEmpty
                && (ingredients ?? []).isEmpty && (directions ?? []).isEmpty
        }
    }

    public static func matchKey(for recipe: Recipe, level: RecipeDuplicateMatchLevel) -> MatchKey {
        switch level {
        case .titleAndSource:
            return .fields(
                FieldKey(
                    name: normalizedText(recipe.name),
                    source: normalizedText(recipe.source),
                    sourceDetails: normalizedText(recipe.sourceDetails),
                    ingredients: nil,
                    directions: nil
                )
            )
        case .ingredientsAndDirections:
            return .fields(
                FieldKey(
                    name: normalizedText(recipe.name),
                    source: normalizedText(recipe.source),
                    sourceDetails: normalizedText(recipe.sourceDetails),
                    // Only the text: a line that changed from a heading to a normal line, or gained
                    // an "is main ingredient" mark, still reads as the same recipe.
                    ingredients: normalizedLines(recipe.ingredients.map(\.text)),
                    directions: normalizedLines(recipe.directions.map(\.text))
                )
            )
        case .allContent:
            return .wholeRecipe(normalized(recipe))
        }
    }

    // MARK: - Normalization

    /// A copy of `recipe` with everything that *can't* meaningfully match between two copies of the
    /// same recipe blanked out, and every remaining text field normalized, so that two normalized
    /// recipes are equal exactly when their content is the same modulo formatting.
    ///
    /// Deliberately a `Recipe` rather than a hand-rolled signature struct: comparing the whole record
    /// means a column added to `Recipe` later is compared automatically instead of being silently
    /// forgotten here. Only the exclusions below need maintaining.
    ///
    /// **Excluded** (all identity or bookkeeping, never content):
    /// - `id`, plus the UUIDs on every nested element. `RecipeDuplicator` (and every import path)
    ///   mints fresh ids for each direction/ingredient/note/variation/preparation time, so a copy
    ///   never shares them with its original -- comparing them would find nothing, ever.
    /// - the image (`imageFilename`, `imageThumbnailData`, `lastModifiedImageDate`):  a copied image
    ///   is a distinct file with a distinct name, and the thumbnail is re-encoded.
    /// - the dates (`createdDate`, `lastModifiedDate`, `lastPrepared`, `lastModifiedPreparedDate`): a
    ///   duplicate is by definition created at a different time, and having cooked one copy but not the
    ///   other shouldn't stop the two being reported as the same recipe.
    /// - the user's own marks on the recipe -- `rating`, `isFavorite`, `wantToMake` -- and `courseId`.
    ///   These drift apart the moment one copy is used: rate one, favorite the other, file one under
    ///   Dessert, and two genuinely identical recipes would stop being reported. Missing a real
    ///   duplicate is worse here than listing two the user can compare and dismiss.
    ///
    /// **Included:** everything else -- name, source, introduction, yield, servings, difficulty, and
    /// all of the ingredient/direction/note/variation/preparation-time/nutrition content. Category
    /// and tag membership lives in junction tables rather than on the row, so like `courseId` it is
    /// not compared.
    public static func normalized(_ recipe: Recipe) -> Recipe {
        var normalized = recipe
        normalized.id = ""
        normalized.imageFilename = nil
        normalized.imageThumbnailData = nil
        normalized.lastModifiedImageDate = nil
        normalized.createdDate = .distantPast
        normalized.lastModifiedDate = .distantPast
        normalized.lastPrepared = nil
        normalized.lastModifiedPreparedDate = nil
        normalized.rating = .notSet
        normalized.isFavorite = false
        normalized.wantToMake = false
        normalized.courseId = nil
        normalized.name = normalizedText(recipe.name)
        normalized.source = normalizedText(recipe.source)
        normalized.sourceDetails = normalizedText(recipe.sourceDetails)
        normalized.introduction = normalizedText(recipe.introduction)
        normalized.yield = normalizedText(recipe.yield)
        // Element ids go, text is normalized, and entries that are blank once normalized drop out --
        // an empty trailing line is invisible in the app and shouldn't split a group.
        normalized.directions = recipe.directions.compactMap { item in
            let text = normalizedText(item.text)
            guard !text.isEmpty else { return nil }
            return Direction(id: "", isHeading: item.isHeading, text: text)
        }
        normalized.ingredients = recipe.ingredients.compactMap { item in
            let text = normalizedText(item.text)
            guard !text.isEmpty else { return nil }
            return Ingredient(id: "", isHeading: item.isHeading, isMain: item.isMain, text: text)
        }
        normalized.notes = recipe.notes.compactMap { item in
            let title = normalizedText(item.title)
            let content = normalizedText(item.content)
            guard !title.isEmpty || !content.isEmpty else { return nil }
            return Note(id: "", title: title, content: content)
        }
        normalized.variations = recipe.variations.compactMap { item in
            let name = normalizedText(item.variationName)
            let text = normalizedText(item.text)
            guard !name.isEmpty || !text.isEmpty else { return nil }
            return Variation(id: "", variationName: name, text: text)
        }
        normalized.preparationTimes = recipe.preparationTimes.compactMap { item in
            let type = normalizedText(item.type)
            let timeString = normalizedText(item.timeString)
            guard !type.isEmpty || !timeString.isEmpty else { return nil }
            return PreparationTime(id: "", type: type, timeString: timeString)
        }
        normalized.nutrition = recipe.nutrition.map { item in
            var item = item
            item.id = ""
            item.servingSize = item.servingSize.map(normalizedText)
            return item
        }
        return normalized
    }

    /// Normalizes each line and drops the ones that end up empty.
    public static func normalizedLines(_ lines: [String]) -> [String] {
        lines.map(normalizedText).filter { !$0.isEmpty }
    }

    /// Folds away the differences a reader can't see: capitalization, runs of whitespace, smart
    /// punctuation, and the typographic fraction glyphs. Two lines that render the same to a cook
    /// should compare the same here.
    ///
    /// This is what makes even `.allContent` tolerant of re-typed text. It matters most for copies
    /// made by scaling: `IngredientScaler` rebuilds a line as `"<quantity> <remainder>"`, so any
    /// original spacing quirk ("1  1/2   cups") comes back normalized and would otherwise read as a
    /// different ingredient.
    public static func normalizedText(_ text: String) -> String {
        // NFC first, so a combining-accent "é" and a precomposed "é" agree.
        var result = text.precomposedStringWithCanonicalMapping

        for (glyph, replacement) in Self.characterReplacements {
            if result.contains(glyph) {
                result = result.replacing(glyph, with: replacement)
            }
        }

        // Collapsing whitespace also absorbs the spaces the fraction replacements introduce.
        return result
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    /// Smart punctuation to its plain equivalent, and the vulgar-fraction glyphs to "n/d". The
    /// fractions get a leading space so "1½" becomes "1 1/2" rather than "11/2"; the whitespace
    /// collapse above tidies up the rest.
    private static let characterReplacements: [(String, String)] = [
        ("\u{2019}", "'"), ("\u{2018}", "'"),                       // ' '
        ("\u{201C}", "\""), ("\u{201D}", "\""),                     // " "
        ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{2212}", "-"),    // – — −
        ("\u{2026}", "..."),                                        // …
        ("\u{00A0}", " "), ("\u{202F}", " "), ("\u{2009}", " "),    // no-break / narrow / thin space
        ("\u{00BD}", " 1/2"),
        ("\u{2153}", " 1/3"), ("\u{2154}", " 2/3"),
        ("\u{00BC}", " 1/4"), ("\u{00BE}", " 3/4"),
        ("\u{2155}", " 1/5"), ("\u{2156}", " 2/5"), ("\u{2157}", " 3/5"), ("\u{2158}", " 4/5"),
        ("\u{2159}", " 1/6"), ("\u{215A}", " 5/6"),
        ("\u{215B}", " 1/8"), ("\u{215C}", " 3/8"), ("\u{215D}", " 5/8"), ("\u{215E}", " 7/8"),
        ("\u{2044}", "/"),                                          // ⁄ fraction slash
    ]
}
