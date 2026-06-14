//
//  RecipeListQueryBuilder.swift
//  Salty
//
//  Builds the main recipe-list query as ONE dynamic SQL statement covering any combination of
//  sidebar scope, enabled search fields, the favorites filter, and sort order/direction.
//
//  This replaces the previous ~1,700 lines in RecipeNavigationSplitViewModel that hand-enumerated
//  individual field combinations as separate literal `#sql` queries — an approach that also had a
//  correctness bug: unhandled combinations (e.g. category + course + tag together) silently fell
//  back to name-only search. Here every enabled field contributes one OR'd condition, uniformly.
//
//  Kept pure and free of view-model state so it can be unit-tested in isolation (see
//  RecipeListQueryBuilderTests): `fragment(...).prepare { _ in "?" }.sql` yields the SQL string.
//

import Foundation
import SQLiteData

/// Which subset of recipes the sidebar selection restricts the list to.
enum RecipeListScope: Equatable {
    case all
    case category(String)
    case course(String)
    case tag(String)
}

enum RecipeListQueryBuilder {

    /// The full `SELECT … FROM recipe [WHERE …] ORDER BY …` statement, ready for `$recipes.load`.
    static func statement(
        scope: RecipeListScope,
        searchPattern: String?,
        options: Set<RecipeListSearchOptions>,
        includeFavorites: Bool,
        sortOrder: RecipeListSortOrderSetting,
        sortDirection: RecipeListSortDirection
    ) -> SQLQueryExpression<Recipe> {
        SQLQueryExpression(
            fragment(
                scope: scope,
                searchPattern: searchPattern,
                options: options,
                includeFavorites: includeFavorites,
                sortOrder: sortOrder,
                sortDirection: sortDirection
            ),
            as: Recipe.self
        )
    }

    /// The raw query fragment (exposed for testing the generated SQL).
    static func fragment(
        scope: RecipeListScope,
        searchPattern: String?,
        options: Set<RecipeListSearchOptions>,
        includeFavorites: Bool,
        sortOrder: RecipeListSortOrderSetting,
        sortDirection: RecipeListSortDirection
    ) -> QueryFragment {
        var conditions: [QueryFragment] = []

        if let scopeCondition = scopeCondition(scope) {
            conditions.append(scopeCondition)
        }
        if let pattern = searchPattern, let search = searchCondition(pattern: pattern, options: options) {
            conditions.append("(\(search))")
        }
        if includeFavorites {
            conditions.append("\(Recipe.isFavorite) = \(bind: true)")
        }

        var sql: QueryFragment = "SELECT \(Recipe.columns) FROM \(Recipe.self)"
        if !conditions.isEmpty {
            sql = "\(sql) WHERE \(conditions.joined(separator: " AND "))"
        }
        sql = "\(sql) ORDER BY \(orderCondition(sortOrder: sortOrder, sortDirection: sortDirection))"
        return sql
    }

    // MARK: - Clauses

    /// Restricts to the selected sidebar item, or nil for "All Recipes".
    static func scopeCondition(_ scope: RecipeListScope) -> QueryFragment? {
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

    /// OR-combined search across whichever fields are enabled. Returns nil when none are active.
    /// `pattern` should already include LIKE wildcards (e.g. "%term%").
    static func searchCondition(pattern: String, options: Set<RecipeListSearchOptions>) -> QueryFragment? {
        let active = options.isEmpty ? [.name] : options
        var conds: [QueryFragment] = []

        if active.contains(.name) {
            conds.append("\(Recipe.name) COLLATE NOCASE LIKE \(bind: pattern)")
        }
        if active.contains(.introduction) {
            conds.append("\(Recipe.introduction) COLLATE NOCASE LIKE \(bind: pattern)")
        }
        if active.contains(.ingredients) {
            conds.append("\(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: pattern)")
        }
        // Notes and variations are JSON arrays. Search only the human-readable value fields via
        // json_each/json_extract rather than LIKE-ing the whole column (which would also match the
        // JSON keys like "content" and the element UUIDs). json_valid guards NULL/invalid columns.
        if active.contains(.notes) {
            conds.append("EXISTS (SELECT 1 FROM json_each(IIF(json_valid(\(Recipe.notes)), \(Recipe.notes), '[]')) WHERE json_extract(value, '$.title') COLLATE NOCASE LIKE \(bind: pattern) OR json_extract(value, '$.content') COLLATE NOCASE LIKE \(bind: pattern))")
        }
        if active.contains(.variations) {
            conds.append("EXISTS (SELECT 1 FROM json_each(IIF(json_valid(\(Recipe.variations)), \(Recipe.variations), '[]')) WHERE json_extract(value, '$.variationName') COLLATE NOCASE LIKE \(bind: pattern) OR json_extract(value, '$.text') COLLATE NOCASE LIKE \(bind: pattern))")
        }
        if active.contains(.course) {
            conds.append("EXISTS (SELECT 1 FROM \(Course.self) WHERE \(Course.id) = \(Recipe.courseId) AND \(Course.name) COLLATE NOCASE LIKE \(bind: pattern))")
        }
        if active.contains(.category) {
            conds.append("EXISTS (SELECT 1 FROM \(RecipeCategory.self) JOIN \(Category.self) ON \(Category.id) = \(RecipeCategory.categoryId) WHERE \(RecipeCategory.recipeId) = \(Recipe.id) AND \(Category.name) COLLATE NOCASE LIKE \(bind: pattern))")
        }
        if active.contains(.tags) {
            conds.append("EXISTS (SELECT 1 FROM \(RecipeTag.self) JOIN \(Tag.self) ON \(Tag.id) = \(RecipeTag.tagId) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: pattern))")
        }

        guard !conds.isEmpty else { return nil }
        return conds.joined(separator: " OR ")
    }

    /// ORDER BY fragment for the given sort order + direction.
    static func orderCondition(
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
        }
    }
}
