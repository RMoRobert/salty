//
//  RecipeToShoppingList.swift
//  Salty
//
//  Turns a recipe's ingredients into shopping list rows: which lines are offered, which of them the
//  destination list already covers, and where the chosen ones land in the list.
//
//  Naming note: this is unrelated to `ShoppingListMerge`, which reconciles a local list against the
//  server during sync. Nothing here talks to sync -- it only produces the new item array that the
//  normal save path then writes.
//

import Foundation
import UUIDV7

public enum RecipeToShoppingList {

    /// One ingredient line offered for adding to a list.
    public struct CandidateItem: Identifiable, Hashable, Sendable {
        /// The source ingredient's id. Stable within the recipe, so it doubles as the picker's
        /// selection key.
        public let id: String
        /// The line as it will be written to the list, with any active scale already applied.
        public let text: String
        /// The ingredient heading this line sits under ("For the sauce"), or nil when the recipe
        /// doesn't group its ingredients. Only groups the picker -- ingredient headings are never
        /// added to the list, which gets one heading per recipe instead.
        public let groupHeading: String?

        public init(id: String, text: String, groupHeading: String? = nil) {
            self.id = id
            self.text = text
            self.groupHeading = groupHeading
        }
    }

    // MARK: - Building candidates

    /// The addable lines of a recipe, in recipe order: headings are dropped (they become the
    /// `groupHeading` of the lines beneath them) and blank lines are skipped.
    public static func candidates(from recipe: Recipe, scaleFactor: Double = 1.0) -> [CandidateItem] {
        var currentHeading: String?
        var candidates: [CandidateItem] = []

        for ingredient in recipe.ingredients {
            let trimmed = ingredient.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if ingredient.isHeading {
                currentHeading = trimmed.isEmpty ? nil : trimmed
                continue
            }
            guard !trimmed.isEmpty else { continue }
            candidates.append(CandidateItem(
                id: ingredient.id,
                text: IngredientScaler.scaledText(for: ingredient, scaleFactor: scaleFactor),
                groupHeading: currentHeading
            ))
        }

        return candidates
    }

    // MARK: - Duplicate detection

    /// Whether the destination list already covers this ingredient, so the picker can start it
    /// unchecked instead of silently adding a second copy.
    ///
    /// Compares what the line is *for* rather than the line itself: quantities, units, and prep
    /// detail are stripped, so "2 cups all-purpose flour" matches an existing "flour".
    ///
    /// Rows deliberately skipped:
    /// - headings, which name a section rather than something to buy
    /// - completed rows, which have already been bought -- a new recipe needing the same thing
    ///   should still add it, otherwise adding to a fully shopped list would add nothing at all
    public static func isAlreadyOnList(_ text: String, existingItems: [ShoppingListListContents]) -> Bool {
        let candidateTokens = matchTokens(text)
        guard !candidateTokens.isEmpty else { return false }

        for item in existingItems {
            guard !(item.isHeading ?? false), !(item.isCompleted ?? false) else { continue }
            let itemTokens = matchTokens(item.text)
            guard !itemTokens.isEmpty else { continue }
            if isSameIngredient(candidateTokens, itemTokens) { return true }
        }

        return false
    }

    /// Whether two reduced ingredient lines name the same thing to buy.
    ///
    /// Identical words are the easy case. The interesting one is a general line against a specific
    /// one, where a plain subset test is too blunt: "flour" ⊂ "all-purpose flour" is the same
    /// ingredient, but "butter" ⊂ "peanut butter" is emphatically not, and the two are structurally
    /// identical -- only knowing what the words mean separates them. So the extra words have to be
    /// ones that qualify an ingredient ("all-purpose", "unsalted") rather than ones that name a
    /// different one ("peanut").
    ///
    /// That gate is what sets the failure mode, and it is set deliberately. An over-eager match
    /// leaves something off the list that the cook needs, and they find out at the shop; a missed
    /// match puts a near-duplicate line on the list, which is visible and takes a swipe to delete.
    /// Unknown words therefore mean "different ingredient", and the qualifier list stays small.
    static func isSameIngredient(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        if lhs == rhs { return true }
        if lhs.isSubset(of: rhs) { return rhs.subtracting(lhs).allSatisfy(qualifierWords.contains) }
        if rhs.isSubset(of: lhs) { return lhs.subtracting(rhs).allSatisfy(qualifierWords.contains) }
        return false
    }

    /// Words that narrow an ingredient without changing what it is, so a line carrying them still
    /// matches the plain form: "unsalted butter" is butter, where "peanut butter" is not.
    public static let qualifierWords: Set<String> = [
        "all", "purpose", "allpurpose", "plain", "self", "rising", "unbleached", "bleached",
        "whole", "half", "low", "reduced", "fat", "free", "skim", "lean", "light", "dark", "heavy",
        "unsalted", "salted", "unsweetened", "sweetened", "granulated", "powdered", "confectioner",
        "brown", "white", "black", "green", "red", "yellow", "golden",
        "virgin", "pure", "natural", "organic", "kosher", "sea", "table", "fine",
        "active", "instant", "dried", "frozen", "canned", "boneless", "skinless", "ripe",
        "unsifted", "sifted", "toasted", "unroasted", "roasted"
    ]

    /// The words that identify what an ingredient line is for, with everything that varies between
    /// two mentions of the same thing removed.
    ///
    /// Correctness here means *consistency*, not linguistics: both sides of a comparison go through
    /// this same reduction, so a stemming rule that mangles a word ("molasses" → "molass") still
    /// matches itself and does no harm.
    public static func matchTokens(_ text: String) -> Set<String> {
        var working = text

        // Parenthetical asides ("(about 2 medium)") and everything after the first comma
        // ("garlic, minced") are detail about handling, not identity.
        while let open = working.firstIndex(of: "("),
              let close = working[open...].firstIndex(of: ")") {
            working.removeSubrange(open...close)
        }
        if let comma = working.firstIndex(of: ",") {
            working = String(working[..<comma])
        }
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return [] }

        // Reuse the display path's quantity parser so "2 cups flour" and "flour" reduce alike. A
        // line that is nothing but a quantity leaves an empty remainder; keep the original words in
        // that case rather than reducing to nothing.
        let remainder = Ingredient(id: "", text: working).parseQuantity().remainder
        let source = remainder.isEmpty ? working : remainder

        let tokens = source
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { singularized(String($0)) }
            .filter { !$0.isEmpty && !ignoredMatchWords.contains($0) }

        return Set(tokens)
    }

    /// Crude, deliberately reversible-free stemming -- see `matchTokens` on why consistency is the
    /// only requirement.
    static func singularized(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ses") || word.hasSuffix("xes") || word.hasSuffix("zes")
            || word.hasSuffix("ches") || word.hasSuffix("shes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ss") { return word }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    /// Words that say nothing about which ingredient a line refers to. Listed singular because
    /// `singularized` runs first. The measurement entries overlap the unit list inside
    /// `parseQuantity` on purpose: that one decides where a quantity ends, this one decides what to
    /// ignore when comparing, and they are free to drift apart.
    public static let ignoredMatchWords: Set<String> = [
        // Measurements, including the ones no quantity precedes ("a pinch of salt").
        "cup", "c", "tablespoon", "tbl", "tbsp", "tbs", "teaspoon", "t", "tsp",
        "gram", "g", "kilogram", "kg", "ounce", "oz", "pound", "lb",
        "milliliter", "ml", "liter", "l", "quart", "qt", "pint", "gallon",
        "package", "pkg", "can", "jar", "bottle", "box", "bag", "container",
        "piece", "pc", "dash", "pinch", "drop", "clove", "stick", "slice", "sprig",
        "head", "bunch", "stalk", "handful",
        // Preparation and size detail.
        "chopped", "minced", "diced", "sliced", "grated", "shredded", "crushed", "cubed",
        "melted", "softened", "beaten", "divided", "optional", "fresh", "freshly",
        "finely", "coarsely", "roughly", "thinly", "large", "small", "medium",
        "ground", "peeled", "seeded", "trimmed", "rinsed", "drained", "packed",
        "cooked", "uncooked", "raw", "warm", "cold", "chilled", "room", "temperature",
        "plus", "more", "extra", "taste", "needed", "serving", "garnish",
        // Stop words.
        "of", "the", "a", "an", "and", "or", "for", "to", "into", "about", "as", "at", "in", "with"
    ]

    // MARK: - Writing into a list

    /// The list's items with the chosen lines appended under a heading named for the recipe.
    ///
    /// Adding the same recipe twice -- a second pass after unchecking something, or a re-scaled
    /// batch -- extends the section it already created rather than repeating the heading, so a list
    /// never grows two "Chili" sections. Existing rows are never rewritten or reordered.
    ///
    /// `makeId` is injectable so tests can assert on the resulting array without matching UUIDs.
    public static func adding(
        _ items: [CandidateItem],
        to existing: [ShoppingListListContents],
        underHeading heading: String?,
        makeId: () -> String = { UUIDV7().uuidString }
    ) -> [ShoppingListListContents] {
        guard !items.isEmpty else { return existing }

        let newRows = items.map { ShoppingListListContents(id: makeId(), text: $0.text) }
        let headingText = heading?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !headingText.isEmpty else { return existing + newRows }

        if let headingIndex = existing.firstIndex(where: {
            ($0.isHeading ?? false)
                && $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(headingText, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            // End of that section: just before the next heading, or the end of the list.
            let afterHeading = existing.index(after: headingIndex)
            let sectionEnd = existing[afterHeading...].firstIndex { $0.isHeading ?? false } ?? existing.endIndex
            var result = existing
            result.insert(contentsOf: newRows, at: sectionEnd)
            return result
        }

        var result = existing
        result.append(ShoppingListListContents(id: makeId(), isHeading: true, text: headingText))
        result.append(contentsOf: newRows)
        return result
    }
}
