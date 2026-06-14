//
//  RecipeListQueryBuilderTests.swift
//  SaltyTests
//
//  Verifies the dynamic recipe-list query builder that replaced the old ~1,700-line
//  combinatorial #sql code. Asserts on the generated SQL text (rendered via
//  QueryFragment.prepare), which is reliable and doesn't execute StructuredQueries
//  generics through the test bundle.
//

import Testing
import Foundation
import SQLiteData
@testable import Salty

struct RecipeListQueryBuilderTests {

    /// Renders a built fragment to plain SQL with "?" placeholders for assertions.
    private func sql(
        scope: RecipeListScope = .all,
        pattern: String? = nil,
        options: Set<RecipeListSearchOptions> = [],
        includeFavorites: Bool = false,
        sortOrder: RecipeListSortOrderSetting = .byName,
        sortDirection: RecipeListSortDirection = .ascending
    ) -> String {
        RecipeListQueryBuilder.fragment(
            scope: scope,
            searchPattern: pattern,
            options: options,
            includeFavorites: includeFavorites,
            sortOrder: sortOrder,
            sortDirection: sortDirection
        ).prepare { _ in "?" }.sql
    }

    // MARK: - Structure

    @Test func allRecipesNoSearchHasNoWhereClause() {
        let s = sql(scope: .all)
        #expect(s.contains("FROM"))
        #expect(!s.contains("WHERE"))
        #expect(s.contains("ORDER BY"))
    }

    @Test func defaultSortIsNameAscending() {
        let s = sql()
        #expect(s.contains("COLLATE NOCASE ASC"))
    }

    @Test func descendingSortEmitsDESC() {
        let s = sql(sortOrder: .byDateCreated, sortDirection: .descending)
        #expect(s.contains("DESC"))
        #expect(!s.contains("ASC"))
    }

    // MARK: - The bug fix: every field combination is honored

    @Test func singleFieldSearchUsesThatFieldOnly() {
        let s = sql(pattern: "%x%", options: [.ingredients])
        #expect(s.contains("ingredients"))
        // Exactly one LIKE → only the one selected field is searched (ORDER BY has no LIKE).
        #expect(s.components(separatedBy: " LIKE ").count - 1 == 1)
    }

    @Test func categoryCourseTagComboSearchesAllThree() {
        // The old code silently fell back to NAME-ONLY for this combination — the core bug.
        let s = sql(pattern: "%x%", options: [.category, .course, .tags])
        #expect(s.contains("recipeCategory"))   // category EXISTS subquery present
        #expect(s.contains("course"))           // course EXISTS subquery present
        #expect(s.contains("recipeTag"))        // tag EXISTS subquery present
        // They must be OR'd together (multiple LIKEs joined by OR), not collapsed to one field.
        #expect(s.contains(" OR "))
    }

    @Test func notesAndVariationsAreIndependentOptions() {
        // SELECT lists every column, so substring checks are unreliable here — count LIKE clauses.
        // Each is its own field and searches two JSON value fields (title+content / name+text),
        // so each contributes two LIKEs via json_extract.
        func likeCount(_ opts: Set<RecipeListSearchOptions>) -> Int {
            sql(pattern: "%x%", options: opts).components(separatedBy: " LIKE ").count - 1
        }
        #expect(likeCount([.notes]) == 2)
        #expect(likeCount([.variations]) == 2)
        #expect(likeCount([.notes, .variations]) == 4)

        // They search JSON values, not the raw column / JSON keys.
        let notesSQL = sql(pattern: "%x%", options: [.notes])
        #expect(notesSQL.contains("json_each"))
        #expect(notesSQL.contains("$.content"))
    }

    @Test func ingredientsSearchJSONTextNotRawColumn() {
        // ingredients is a JSON array of {id, isHeading, isMain, text}; search the human-readable
        // `text` value via json_each rather than LIKE-ing the whole column (which would also match
        // JSON keys and element UUIDs).
        let s = sql(pattern: "%x%", options: [.ingredients])
        #expect(s.contains("json_each"))
        #expect(s.contains("$.text"))
        // One value field → exactly one LIKE.
        #expect(s.components(separatedBy: " LIKE ").count - 1 == 1)
    }

    @Test func emptyOptionsDefaultToName() {
        let s = sql(pattern: "%x%", options: [])
        #expect(s.contains("name"))
    }

    @Test func multipleTextFieldsAreOrCombined() {
        let s = sql(pattern: "%x%", options: [.name, .introduction, .ingredients])
        #expect(s.contains(" OR "))
        #expect(s.contains("name"))
        #expect(s.contains("introduction"))
        #expect(s.contains("ingredients"))
    }

    // MARK: - Scope + filters compose with AND

    @Test func categoryScopeAddsExistsAndKeepsSearch() {
        let s = sql(scope: .category("cat-1"), pattern: "%x%", options: [.name])
        #expect(s.contains("WHERE"))
        #expect(s.contains("recipeCategory"))
        #expect(s.contains(" AND "))   // scope AND (search)
    }

    @Test func courseScopeFiltersByCourseId() {
        let s = sql(scope: .course("course-1"))
        #expect(s.contains("courseId"))
        #expect(s.contains("WHERE"))
    }

    @Test func favoritesFilterAddsIsFavorite() {
        let s = sql(scope: .all, includeFavorites: true)
        #expect(s.contains("isFavorite"))
        #expect(s.contains("WHERE"))
    }

    @Test func scopeSearchAndFavoritesAllCombine() {
        let s = sql(scope: .tag("tag-1"), pattern: "%x%", options: [.name], includeFavorites: true)
        #expect(s.contains("recipeTag"))    // scope
        #expect(s.contains("name"))         // search
        #expect(s.contains("isFavorite"))   // favorites
        // Three top-level conditions joined by AND.
        let andCount = s.components(separatedBy: " AND ").count - 1
        #expect(andCount >= 2)
    }

    // MARK: - Binding count (each LIKE / id contributes one placeholder)

    @Test func bindingsMatchPlaceholders() {
        let (sqlText, bindings) = RecipeListQueryBuilder.fragment(
            scope: .category("cat-1"),
            searchPattern: "%x%",
            options: [.name, .introduction],
            includeFavorites: true,
            sortOrder: .byName,
            sortDirection: .ascending
        ).prepare { _ in "?" }
        // category id + 2 search LIKEs + favorites bool = 4 placeholders/bindings
        #expect(sqlText.filter { $0 == "?" }.count == bindings.count)
        #expect(bindings.count == 4)
    }
}
