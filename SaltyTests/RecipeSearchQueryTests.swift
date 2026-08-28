//
//  RecipeSearchQueryTests.swift
//  SaltyTests
//
//  The structured search model and the adapter that maps the recipe list's "Search In…" checkboxes
//  onto it. The list's own behaviour is pinned in RecipeListQueryBuilderTests; what matters here is
//  that the model expresses it exactly (the adapter is the only thing standing between the shipping
//  search and a rewrite of how it's built) and that the pieces the advanced search builder will need
//  -- nesting, mixed all/any, persistence -- already hold up.
//

import Testing
import Foundation
import SQLiteData
@testable import Salty
import SaltyCore

struct RecipeSearchQueryTests {

    /// Renders a fragment to plain SQL with "?" placeholders, as the other query-builder tests do.
    private func sql(_ fragment: QueryFragment?) -> String? {
        fragment?.prepare { _ in "?" }.sql
    }

    private func listSQL(
        scope: RecipeListScope = .all,
        pattern: String? = nil,
        options: Set<RecipeListSearchOptions> = [],
        includeFavorites: Bool = false,
        includeWantToMake: Bool = false
    ) -> String {
        RecipeListQueryBuilder.fragment(
            scope: scope,
            searchPattern: pattern,
            options: options,
            includeFavorites: includeFavorites,
            includeWantToMake: includeWantToMake,
            sortOrder: .byName,
            sortDirection: .ascending
        ).prepare { _ in "?" }.sql
    }

    private func modelSQL(scope: RecipeListScope = .all, _ query: RecipeSearchQuery) -> String {
        RecipeListQueryBuilder.fragment(
            scope: scope,
            query: query,
            sortOrder: .byName,
            sortDirection: .ascending
        ).prepare { _ in "?" }.sql
    }

    // MARK: - Match kinds

    @Test func matchKindsBuildTheirLikePatterns() {
        #expect(RecipeTextMatch.contains.pattern(for: "chicken") == "%chicken%")
        #expect(RecipeTextMatch.beginsWith.pattern(for: "chicken") == "chicken%")
        #expect(RecipeTextMatch.endsWith.pattern(for: "chicken") == "%chicken")
        #expect(RecipeTextMatch.equals.pattern(for: "chicken") == "chicken")
        // The search field wraps its own term, so this kind must pass the value through untouched.
        #expect(RecipeTextMatch.likePattern.pattern(for: "%chicken%") == "%chicken%")
    }

    // MARK: - Building

    @Test func anyOfOrdersFieldsDeterministically() {
        // Same fields, two different set literals -- the rendered SQL must not depend on set order.
        let a = RecipeSearchQuery.anyOf(fields: [.tags, .name, .ingredients], matching: "%x%")
        let b = RecipeSearchQuery.anyOf(fields: [.ingredients, .tags, .name], matching: "%x%")
        #expect(modelSQL(a) == modelSQL(b))

        let fields: [RecipeSearchField] = a.criteria.compactMap {
            if case .text(let field, _, _) = $0 { return field }
            return nil
        }
        #expect(fields == [.name, .ingredients, .tags])
    }

    // MARK: - Rendering

    @Test func emptyQueryRendersNoCondition() {
        #expect(RecipeListQueryBuilder.condition(for: RecipeSearchQuery()) == nil)
        // …and therefore no WHERE clause at all.
        #expect(!modelSQL(RecipeSearchQuery()).contains("WHERE"))
    }

    @Test func blankTextCriterionIsInertRatherThanMatchingEverything() {
        // A half-filled builder row must not widen the results to the whole library.
        let blank = RecipeSearchCriterion.text(field: .name, match: .contains, value: "")
        #expect(RecipeListQueryBuilder.condition(for: blank) == nil)

        let query = RecipeSearchQuery(.all, [blank, .isFavorite(true)])
        let s = modelSQL(query)
        #expect(!s.contains("LIKE"))
        #expect(s.contains("isFavorite"))
    }

    @Test func singleConditionIsNotParenthesizedButSeveralAre() {
        let one = sql(RecipeListQueryBuilder.condition(for: RecipeSearchQuery(.any, [.isFavorite(true)])))
        #expect(one?.hasPrefix("(") == false)

        let two = sql(RecipeListQueryBuilder.condition(for: RecipeSearchQuery(.any, [.isFavorite(true), .wantToMake(true)])))
        #expect(two?.hasPrefix("(") == true)
        #expect(two?.contains(" OR ") == true)
    }

    @Test func nestedGroupKeepsItsOwnCombinator() {
        // "favorite AND (name OR tags)" -- the inner OR has to stay parenthesized, or the AND would
        // bind tighter and silently change the meaning.
        let query = RecipeSearchQuery(.all, [
            .isFavorite(true),
            .group(RecipeSearchQuery.anyOf(fields: [.name, .tags], matching: "%x%")),
        ])
        let s = modelSQL(query)
        #expect(s.contains(" AND ("))
        #expect(s.contains(" OR "))
        #expect(s.components(separatedBy: " LIKE ").count - 1 == 2)
    }

    @Test func allAndAnyPickTheirOperator() {
        let all = modelSQL(RecipeSearchQuery(.all, [.isFavorite(true), .wantToMake(true)]))
        #expect(all.contains(" AND "))
        #expect(!all.contains(" OR "))

        let any = modelSQL(RecipeSearchQuery(.any, [.isFavorite(true), .wantToMake(true)]))
        #expect(any.contains(" OR "))
    }

    @Test func scopeStillComposesWithTheQuery() {
        let s = modelSQL(scope: .category("c1"), RecipeSearchQuery(.any, [.isFavorite(true)]))
        #expect(s.contains("recipeCategory"))
        #expect(s.contains(" AND "))
    }

    // MARK: - The adapter: the shipping search, expressed in the model

    @Test func checkboxSearchMapsToOneOrGroupPerTerm() {
        let query = RecipeListQueryBuilder.query(
            searchPattern: "%x%",
            options: [.name, .mainIngredients],
            includeFavorites: true,
            includeWantToMake: false
        )
        #expect(query.combinator == .all)
        #expect(query.criteria.count == 2)   // the OR'd fields, plus the favorites filter

        guard case .group(let fields) = query.criteria.first else {
            Issue.record("expected the search fields to be grouped")
            return
        }
        #expect(fields.combinator == .any)
        #expect(fields.criteria.count == 2)
        // The list hands over a ready-made pattern, so nothing may re-wrap it.
        if case .text(_, let match, let value) = fields.criteria[0] {
            #expect(match == .likePattern)
            #expect(value == "%x%")
        } else {
            Issue.record("expected a text criterion")
        }
    }

    @Test func noPatternMeansNoTextCriteria() {
        // An empty search box leaves only whatever filters are on -- never LIKE '%%'.
        let query = RecipeListQueryBuilder.query(
            searchPattern: nil, options: [.name], includeFavorites: true, includeWantToMake: true
        )
        #expect(query.criteria.count == 2)
        #expect(query.criteria.allSatisfy { if case .text = $0 { return false } else { return true } })
    }

    @Test func noCheckedFieldsStillSearchesNames() {
        let query = RecipeListQueryBuilder.query(
            searchPattern: "%x%", options: [], includeFavorites: false, includeWantToMake: false
        )
        guard case .group(let fields) = query.criteria.first else {
            Issue.record("expected the search fields to be grouped")
            return
        }
        #expect(fields.criteria == [.text(field: .name, match: .likePattern, value: "%x%")])
    }

    @Test func adapterRendersTheSameSQLAsTheListPathForEveryFieldCombination() {
        // The equivalence that makes this a refactor and not a behaviour change: whatever the list
        // asks for, going through the model produces the same statement.
        let cases: [(Set<RecipeListSearchOptions>, Bool, Bool)] = [
            ([], false, false),
            ([.name], false, false),
            ([.mainIngredients], false, false),
            ([.ingredients, .mainIngredients], false, false),
            ([.name, .introduction, .notes, .variations], true, false),
            ([.category, .course, .tags], false, true),
            (Set(RecipeListSearchOptions.allCases), true, true),
        ]
        for (options, favorites, wantToMake) in cases {
            for pattern in [nil, "%x%"] as [String?] {
                for scope in [RecipeListScope.all, .category("c1"), .course("co1"), .tag("t1")] {
                    let viaList = listSQL(
                        scope: scope, pattern: pattern, options: options,
                        includeFavorites: favorites, includeWantToMake: wantToMake
                    )
                    let viaModel = modelSQL(
                        scope: scope,
                        RecipeListQueryBuilder.query(
                            searchPattern: pattern, options: options,
                            includeFavorites: favorites, includeWantToMake: wantToMake
                        )
                    )
                    #expect(viaList == viaModel)
                }
            }
        }
    }

    @Test func everySearchOptionHasItsOwnField() {
        // A new checkbox that forgets its field mapping would silently search the wrong column.
        let fields = RecipeListSearchOptions.allCases.map(\.searchField)
        #expect(Set(fields).count == RecipeListSearchOptions.allCases.count)
    }

    // MARK: - Persistence (saved smart lists will store these)

    @Test func queryRoundTripsThroughJSON() throws {
        let query = RecipeSearchQuery(.all, [
            .text(field: .mainIngredients, match: .contains, value: "chicken"),
            .isFavorite(true),
            .wantToMake(false),
            .group(RecipeSearchQuery(.any, [
                .text(field: .tags, match: .equals, value: "weeknight"),
                .text(field: .notes, match: .beginsWith, value: "Freezes"),
            ])),
        ])
        let data = try JSONEncoder().encode(query)
        let decoded = try JSONDecoder().decode(RecipeSearchQuery.self, from: data)
        #expect(decoded == query)
    }
}
