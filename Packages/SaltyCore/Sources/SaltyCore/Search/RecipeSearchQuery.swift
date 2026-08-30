//
//  RecipeSearchQuery.swift
//  SaltyCore
//
//  The structured form of a recipe search: criteria combined with "match all" or "match any", which
//  RecipeListQueryBuilder renders to SQL.
//
//  The recipe list's "Search In…" checkboxes are one shape of this and nothing more -- one term OR'd
//  across the checked fields -- so they map onto it via `RecipeSearchQuery.anyOf(...)` rather than
//  being their own query path (see RecipeListQueryBuilder.query(searchPattern:options:…)). What the
//  advanced search builder will need on top of that -- mixed all/any, nested groups, criteria that
//  aren't text at all -- is a new case here plus one render branch in the builder; no view model or
//  query plumbing has to change again.
//
//  Everything here is a plain value type with no SQL and no SQLiteData import, so it unit-tests on
//  its own and is Codable -- which is what saved smart lists will persist.
//

import Foundation

/// A text field a search can look in. Mirrors `RecipeListSearchOptions` (the user's checkbox
/// preferences) but stays separate from it: a saved query names fields for good, while the
/// preference enum is free to change what it offers, gain UI-only entries, or be reordered.
///
/// Declaration order is the order conditions are rendered in, which keeps generated SQL stable.
public enum RecipeSearchField: String, Codable, Hashable, CaseIterable, Sendable {
    case name
    case introduction
    case ingredients
    /// Only the ingredient lines flagged `isMain`, so "chicken" doesn't match a teaspoon of stock.
    case mainIngredients
    case notes
    case variations
    case course
    case category
    case tags
}

/// How a text criterion's value is matched. Every case renders to `LIKE` under `COLLATE NOCASE`,
/// so all matching is case-insensitive.
public enum RecipeTextMatch: String, Codable, Hashable, CaseIterable, Sendable {
    case contains
    case beginsWith
    case endsWith
    /// Equality in the same case-insensitive sense as the rest -- `LIKE` with no wildcards.
    case equals
    /// The value is already a LIKE pattern, wildcards included. What the plain search field passes,
    /// since it wraps the typed term itself.
    case likePattern

    /// The LIKE pattern this match makes of `value`.
    ///
    /// `value` is used as-is: `%` and `_` typed by the user still act as wildcards, which is the
    /// behaviour the search field has always had.
    public func pattern(for value: String) -> String {
        switch self {
        case .contains:
            return "%\(value)%"
        case .beginsWith:
            return "\(value)%"
        case .endsWith:
            return "%\(value)"
        case .equals, .likePattern:
            return value
        }
    }
}

/// One condition in a search.
///
/// New kinds of criteria (rating, last prepared, has photo, difficulty, …) go here as cases, and get
/// one branch each in `RecipeListQueryBuilder.condition(for:)`. Nothing else needs to know.
public enum RecipeSearchCriterion: Codable, Hashable, Sendable {
    /// `field` matches `value` under `match`. An empty `value` makes the criterion inert (it renders
    /// to nothing) rather than matching every recipe -- a half-filled builder row shouldn't widen the
    /// results.
    case text(field: RecipeSearchField, match: RecipeTextMatch, value: String)
    case isFavorite(Bool)
    case wantToMake(Bool)
    /// A nested query, for "all of these AND any of those".
    case group(RecipeSearchQuery)
}

/// A list of criteria and how to combine them.
public struct RecipeSearchQuery: Codable, Hashable, Sendable {

    /// Whether every criterion must match (`AND`) or any one of them (`OR`).
    public enum Combinator: String, Codable, Hashable, CaseIterable, Sendable {
        case all
        case any
    }

    public var combinator: Combinator
    public var criteria: [RecipeSearchCriterion]

    public init(_ combinator: Combinator = .all, _ criteria: [RecipeSearchCriterion] = []) {
        self.combinator = combinator
        self.criteria = criteria
    }

    /// True when there is nothing to match on, which the builder renders as "no WHERE clause".
    /// Criteria that are themselves inert (an empty search term, an empty group) still count as
    /// present here; the builder drops them when rendering.
    public var isEmpty: Bool { criteria.isEmpty }

    /// One term across several fields, OR'd -- the shape the recipe list's search field produces.
    ///
    /// Fields are ordered by `RecipeSearchField.allCases` rather than by the set's iteration order,
    /// so the same selection always renders the same SQL.
    public static func anyOf(
        fields: Set<RecipeSearchField>,
        matching value: String,
        match: RecipeTextMatch = .likePattern
    ) -> RecipeSearchQuery {
        RecipeSearchQuery(
            .any,
            RecipeSearchField.allCases
                .filter(fields.contains)
                .map { .text(field: $0, match: match, value: value) }
        )
    }
}

extension RecipeListSearchOptions {
    /// The search-model field this checkbox stands for.
    public var searchField: RecipeSearchField {
        switch self {
        case .name:
            return .name
        case .ingredients:
            return .ingredients
        case .mainIngredients:
            return .mainIngredients
        case .introduction:
            return .introduction
        case .category:
            return .category
        case .course:
            return .course
        case .tags:
            return .tags
        case .notes:
            return .notes
        case .variations:
            return .variations
        }
    }
}
