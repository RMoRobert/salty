//
//  RecipeListQueryBuilder.swift
//  Salty
//
//  Builds the main recipe-list query as ONE dynamic SQL statement covering any combination of
//  sidebar scope, enabled search fields, the favorites filter, and sort order/direction.
//
//  The WHERE clause is rendered from a `RecipeSearchQuery` (see Search/RecipeSearchQuery.swift):
//  criteria combined with all/any, nestable. The recipe list's checkbox search is one shape of that
//  and reaches it through `query(searchPattern:options:…)`, so the shipping search and any future
//  advanced/saved search render through the same code. Adding a criterion kind means a case in the
//  model and a branch in `condition(for:)` -- nothing else.
//
//  This replaces the previous ~1,700 lines in RecipeNavigationSplitViewModel that hand-enumerated
//  individual field combinations as separate literal `#sql` queries -- an approach that also had a
//  correctness bug: unhandled combinations (e.g. category + course + tag together) silently fell
//  back to name-only search. Here every enabled field contributes one OR'd condition, uniformly.
//
//  Kept pure and free of view-model state so it can be unit-tested in isolation (see
//  RecipeListQueryBuilderTests): `fragment(...).prepare { _ in "?" }.sql` yields the SQL string.
//

import Foundation
import SQLiteData

/// Which subset of recipes the sidebar selection restricts the list to.
public enum RecipeListScope: Equatable {
    case all
    case category(String)
    case course(String)
    case tag(String)
}

public enum RecipeListQueryBuilder {

    /// The full `SELECT … FROM recipe [WHERE …] ORDER BY …` statement, ready for `$recipes.load`.
    /// Selects the lightweight `RecipeListItem` projection rather than full recipe rows.
    public static func statement(
        scope: RecipeListScope,
        query: RecipeSearchQuery,
        sortOrder: RecipeListSortOrderSetting,
        sortDirection: RecipeListSortDirection
    ) -> SQLQueryExpression<RecipeListItem> {
        SQLQueryExpression(
            fragment(scope: scope, query: query, sortOrder: sortOrder, sortDirection: sortDirection),
            as: RecipeListItem.self
        )
    }

    /// The recipe list's own call: sidebar scope, one term across the checked "Search In…" fields,
    /// and the two smart-list filters. Everything after `scope` is folded into a `RecipeSearchQuery`
    /// (see `query(searchPattern:options:includeFavorites:includeWantToMake:)`) and rendered by the
    /// same code path a saved advanced search will use.
    public static func statement(
        scope: RecipeListScope,
        searchPattern: String?,
        options: Set<RecipeListSearchOptions>,
        includeFavorites: Bool,
        includeWantToMake: Bool = false,
        sortOrder: RecipeListSortOrderSetting,
        sortDirection: RecipeListSortDirection
    ) -> SQLQueryExpression<RecipeListItem> {
        statement(
            scope: scope,
            query: query(
                searchPattern: searchPattern,
                options: options,
                includeFavorites: includeFavorites,
                includeWantToMake: includeWantToMake
            ),
            sortOrder: sortOrder,
            sortDirection: sortDirection
        )
    }

    /// The raw query fragment (exposed for testing the generated SQL).
    public static func fragment(
        scope: RecipeListScope,
        query: RecipeSearchQuery,
        sortOrder: RecipeListSortOrderSetting,
        sortDirection: RecipeListSortDirection
    ) -> QueryFragment {
        var conditions: [QueryFragment] = []

        // Scope stays outside the search query: it comes from the sidebar selection, not from
        // anything the user typed or saved. Folding it in as criteria is what a saved smart list
        // ("everything in Desserts rated 4+") would want, and is the next natural step here.
        if let scopeCondition = scopeCondition(scope) {
            conditions.append(scopeCondition)
        }
        if let searchCondition = condition(for: query) {
            conditions.append(searchCondition)
        }

        // Lightweight projection. The column order here MUST match RecipeListItem's stored-property
        // order -- the raw-SQL decoder reads columns positionally.
        var sql: QueryFragment = "SELECT \(Recipe.id), \(Recipe.name), \(Recipe.source), \(Recipe.sourceDetails), \(Recipe.introduction), \(Recipe.createdDate), \(Recipe.lastModifiedDate), \(Recipe.rating), \(Recipe.isFavorite), \(Recipe.imageThumbnailData), \(Recipe.lastPrepared) FROM \(Recipe.self)"
        if !conditions.isEmpty {
            sql = "\(sql) WHERE \(conditions.joined(separator: " AND "))"
        }
        sql = "\(sql) ORDER BY \(orderCondition(sortOrder: sortOrder, sortDirection: sortDirection))"
        return sql
    }

    /// Same as above for the recipe list's checkbox search; see the matching `statement` overload.
    public static func fragment(
        scope: RecipeListScope,
        searchPattern: String?,
        options: Set<RecipeListSearchOptions>,
        includeFavorites: Bool,
        includeWantToMake: Bool = false,
        sortOrder: RecipeListSortOrderSetting,
        sortDirection: RecipeListSortDirection
    ) -> QueryFragment {
        fragment(
            scope: scope,
            query: query(
                searchPattern: searchPattern,
                options: options,
                includeFavorites: includeFavorites,
                includeWantToMake: includeWantToMake
            ),
            sortOrder: sortOrder,
            sortDirection: sortDirection
        )
    }

    // MARK: - The checkbox search, as a query

    /// Maps the recipe list's search state onto the structured model: one term OR'd across the
    /// checked fields, AND'ed with whichever smart-list filters are on.
    ///
    /// `searchPattern` is a ready-made LIKE pattern (the list wraps the typed term in `%…%` itself),
    /// hence `.likePattern`. No pattern means no text criteria at all -- an empty term must not
    /// render as `LIKE '%%'`.
    public static func query(
        searchPattern: String?,
        options: Set<RecipeListSearchOptions>,
        includeFavorites: Bool,
        includeWantToMake: Bool = false
    ) -> RecipeSearchQuery {
        var criteria: [RecipeSearchCriterion] = []

        if let pattern = searchPattern, !pattern.isEmpty {
            // No boxes checked still means "search names", the way it always has.
            let active = options.isEmpty ? [RecipeListSearchOptions.name] : options
            criteria.append(
                .group(RecipeSearchQuery.anyOf(fields: Set(active.map(\.searchField)), matching: pattern))
            )
        }
        if includeFavorites {
            criteria.append(.isFavorite(true))
        }
        if includeWantToMake {
            criteria.append(.wantToMake(true))
        }
        return RecipeSearchQuery(.all, criteria)
    }

    // MARK: - Clauses

    /// Restricts to the selected sidebar item, or nil for "All Recipes".
    public static func scopeCondition(_ scope: RecipeListScope) -> QueryFragment? {
        switch scope {
        case .all:
            return nil
        case .category(let id):
            return "EXISTS (SELECT 1 FROM \(RecipeCategory.self) WHERE \(RecipeCategory.recipeId) = \(Recipe.id) AND \(RecipeCategory.categoryId) = \(bind: id))"
        case .course(let id):
            return "\(Recipe.courseId) = \(bind: id)"
        case .tag(let id):
            return "EXISTS (SELECT 1 FROM \(RecipeTag.self) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(RecipeTag.tagId) = \(bind: id))"
        }
    }

    /// A whole query as one condition, or nil when nothing in it can match on (no criteria, or only
    /// inert ones such as a blank search term). Parenthesised only when it holds more than one
    /// condition, so a query nested inside another can't have its combinator swallowed.
    public static func condition(for query: RecipeSearchQuery) -> QueryFragment? {
        let conds = query.criteria.compactMap(condition(for:))
        guard let first = conds.first else { return nil }
        guard conds.count > 1 else { return first }
        let separator: QueryFragment = query.combinator == .all ? " AND " : " OR "
        return "(\(conds.joined(separator: separator)))"
    }

    /// One criterion as a condition, or nil when it is inert.
    public static func condition(for criterion: RecipeSearchCriterion) -> QueryFragment? {
        switch criterion {
        case .text(let field, let match, let value):
            // An empty term renders to nothing rather than LIKE '%%', which would match everything.
            guard !value.isEmpty else { return nil }
            return textCondition(field: field, pattern: match.pattern(for: value))
        case .isFavorite(let flag):
            return "\(Recipe.isFavorite) = \(bind: flag)"
        case .wantToMake(let flag):
            return "\(Recipe.wantToMake) = \(bind: flag)"
        case .group(let nested):
            return condition(for: nested)
        }
    }

    /// The LIKE test for one searchable text field. Every field is matched `COLLATE NOCASE`.
    public static func textCondition(field: RecipeSearchField, pattern: String) -> QueryFragment {
        switch field {
        case .name:
            return "\(Recipe.name) COLLATE NOCASE LIKE \(bind: pattern)"
        case .introduction:
            return "\(Recipe.introduction) COLLATE NOCASE LIKE \(bind: pattern)"
        case .ingredients:
            // ingredients is a JSON array of {id, isHeading, isMain, text}. Match only the
            // human-readable `text` via json_each/json_extract rather than LIKE-ing the whole
            // column (which would also match the JSON keys and element UUIDs).
            return "EXISTS (SELECT 1 FROM json_each(IIF(json_valid(\(Recipe.ingredients)), \(Recipe.ingredients), '[]')) WHERE json_extract(value, '$.text') COLLATE NOCASE LIKE \(bind: pattern))"
        case .mainIngredients:
            // The same array, narrowed to the lines the editor flagged as main ingredients -- the one
            // way to ask "recipes whose *main* ingredient is chicken" without hits from a garnish or a
            // teaspoon of stock. A missing or false flag reads as NULL/0 and drops out, so rows written
            // before the flag existed simply don't match.
            return "EXISTS (SELECT 1 FROM json_each(IIF(json_valid(\(Recipe.ingredients)), \(Recipe.ingredients), '[]')) WHERE json_extract(value, '$.isMain') = 1 AND json_extract(value, '$.text') COLLATE NOCASE LIKE \(bind: pattern))"
        // Notes and variations are JSON arrays too. Search only the human-readable value fields, for
        // the same reason: LIKE-ing the whole column would also match the JSON keys like "content"
        // and the element UUIDs. json_valid guards NULL/invalid columns.
        case .notes:
            return "EXISTS (SELECT 1 FROM json_each(IIF(json_valid(\(Recipe.notes)), \(Recipe.notes), '[]')) WHERE json_extract(value, '$.title') COLLATE NOCASE LIKE \(bind: pattern) OR json_extract(value, '$.content') COLLATE NOCASE LIKE \(bind: pattern))"
        case .variations:
            return "EXISTS (SELECT 1 FROM json_each(IIF(json_valid(\(Recipe.variations)), \(Recipe.variations), '[]')) WHERE json_extract(value, '$.variationName') COLLATE NOCASE LIKE \(bind: pattern) OR json_extract(value, '$.text') COLLATE NOCASE LIKE \(bind: pattern))"
        case .course:
            return "EXISTS (SELECT 1 FROM \(Course.self) WHERE \(Course.id) = \(Recipe.courseId) AND \(Course.name) COLLATE NOCASE LIKE \(bind: pattern))"
        case .category:
            return "EXISTS (SELECT 1 FROM \(RecipeCategory.self) JOIN \(Category.self) ON \(Category.id) = \(RecipeCategory.categoryId) WHERE \(RecipeCategory.recipeId) = \(Recipe.id) AND \(Category.name) COLLATE NOCASE LIKE \(bind: pattern))"
        case .tags:
            return "EXISTS (SELECT 1 FROM \(RecipeTag.self) JOIN \(Tag.self) ON \(Tag.id) = \(RecipeTag.tagId) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: pattern))"
        }
    }

    /// OR-combined search across whichever fields are enabled. Returns nil when none are active.
    /// `pattern` should already include LIKE wildcards (e.g. "%term%").
    public static func searchCondition(pattern: String, options: Set<RecipeListSearchOptions>) -> QueryFragment? {
        let active = options.isEmpty ? [RecipeListSearchOptions.name] : options
        return condition(for: .anyOf(fields: Set(active.map(\.searchField)), matching: pattern))
    }

    /// ORDER BY fragment for the given sort order + direction.
    public static func orderCondition(
        sortOrder: RecipeListSortOrderSetting,
        sortDirection: RecipeListSortDirection
    ) -> QueryFragment {
        let direction: QueryFragment = sortDirection == .descending ? "DESC" : "ASC"
        switch sortOrder {
        case .byName:         return "\(Recipe.name) COLLATE NOCASE \(direction)"
        case .bySource:       return "\(Recipe.source) COLLATE NOCASE \(direction)"
        case .byDateModified: return "\(Recipe.lastModifiedDate) \(direction)"
        case .byDateCreated:  return "\(Recipe.createdDate) \(direction)"
        case .byRating:       return "\(Recipe.rating) \(direction)"
        case .byDifficulty:   return "\(Recipe.difficulty) \(direction)"
        // Never-made recipes sort LAST in BOTH directions. SQLite puts NULLs first when ascending, which
        // would fill the top of the list with recipes that have no date at all — for a sort whose whole
        // point is "what have I cooked lately", those belong at the bottom whichever way it's pointed.
        case .byLastMade:     return "\(Recipe.lastPrepared) IS NULL, \(Recipe.lastPrepared) \(direction)"
        }
    }
}
