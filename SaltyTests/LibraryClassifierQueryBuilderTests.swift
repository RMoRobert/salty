//
//  LibraryClassifierQueryBuilderTests.swift
//  SaltyTests
//
//  Verifies the classifier-editor list query. Asserts on the generated SQL text (rendered via
//  QueryFragment.prepare), the same approach RecipeListQueryBuilderTests uses: reliable, and it
//  doesn't execute StructuredQueries generics through the test bundle.
//

import Testing
import Foundation
import SQLiteData
@testable import Salty
import SaltyCore

struct LibraryClassifierQueryBuilderTests {

    /// Renders a built fragment to plain SQL with "?" placeholders for assertions.
    private func sql(
        _ classifier: LibraryClassifier,
        pattern: String? = nil,
        column: LibraryClassifierSortColumn = .name,
        ascending: Bool = true
    ) -> String {
        LibraryClassifierQueryBuilder.fragment(
            classifier: classifier,
            searchPattern: pattern,
            column: column,
            ascending: ascending
        ).prepare { _ in "?" }.sql
    }

    // MARK: - Structure

    @Test func selectsTheClassifiersOwnTable() {
        #expect(sql(.category).contains(#"FROM "category""#))
        #expect(sql(.course).contains(#"FROM "course""#))
        #expect(sql(.tag).contains(#"FROM "tag""#))
    }

    /// No top-level filter without a search. (The usage-count subquery has a WHERE of its own, so this
    /// checks the outer query goes straight from FROM to ORDER BY.)
    @Test func noSearchHasNoWhereClause() {
        #expect(sql(.tag).contains(#"FROM "tag" ORDER BY"#))
    }

    @Test func searchPatternIsBoundNotInterpolated() {
        let s = sql(.tag, pattern: "%dess%")
        #expect(s.contains("COLLATE NOCASE LIKE ?"))
        #expect(!s.contains("dess"))
    }

    /// The column order has to match LibraryClassifierItem's stored properties -- the raw-SQL decoder
    /// reads positionally, so a reordering here would silently mis-decode every row.
    @Test func projectionIsIdThenNameThenCount() {
        let s = sql(.category)
        let id = try! #require(s.range(of: #""category"."id""#))
        let name = try! #require(s.range(of: #"AS "name""#))
        let count = try! #require(s.range(of: #"AS "recipeCount""#))
        #expect(id.lowerBound < name.lowerBound)
        #expect(name.lowerBound < count.lowerBound)
    }

    @Test func nameIsNullCoalescedSoARowWithNoNameStillDecodes() {
        #expect(sql(.tag).contains("IFNULL"))
    }

    // MARK: - Usage counts

    @Test func categoriesAndTagsCountDistinctRecipesThroughTheirJunctionTable() {
        #expect(sql(.category).contains(#"COUNT(DISTINCT "recipeId") FROM "recipeCategory""#))
        #expect(sql(.tag).contains(#"COUNT(DISTINCT "recipeId") FROM "recipeTag""#))
    }

    /// A recipe holds at most one course, so there is nothing to de-duplicate -- and no junction table.
    @Test func coursesCountRecipesByForeignKey() {
        let s = sql(.course)
        #expect(s.contains(#"COUNT(*) FROM "recipe" WHERE "courseId""#))
        #expect(!s.contains("junction"))
    }

    // MARK: - Sorting

    @Test func defaultSortIsNameAscendingCaseInsensitive() {
        #expect(sql(.tag).hasSuffix(#"ORDER BY "name" COLLATE NOCASE ASC"#))
    }

    /// The macOS table header can flip either column; direction reaches the SQL.
    @Test func nameDescendingFlipsTheDirection() {
        #expect(sql(.tag, column: .name, ascending: false).hasSuffix(#"ORDER BY "name" COLLATE NOCASE DESC"#))
    }

    @Test func countDescendingSortsByCountThenName() {
        let s = sql(.tag, column: .recipeCount, ascending: false)
        #expect(s.contains(#"ORDER BY "recipeCount" DESC"#))
        #expect(s.hasSuffix(#""name" COLLATE NOCASE ASC"#))
    }

    /// Whichever way the count column points, the name tie-break stays ascending, so rows with equal
    /// counts remain scannable.
    @Test func countAscendingKeepsTheNameTiebreakAscending() {
        let s = sql(.tag, column: .recipeCount, ascending: true)
        #expect(s.contains(#"ORDER BY "recipeCount" ASC"#))
        #expect(s.hasSuffix(#""name" COLLATE NOCASE ASC"#))
    }

    // MARK: - iOS menu mapping

    /// The iOS sort menu's two options map onto the column + direction the query builder takes.
    @Test func menuOptionsMapToColumnAndDirection() {
        #expect(LibraryClassifierSortOrder.name.column == .name)
        #expect(LibraryClassifierSortOrder.name.ascending)
        #expect(LibraryClassifierSortOrder.mostUsed.column == .recipeCount)
        #expect(!LibraryClassifierSortOrder.mostUsed.ascending)
    }
}
