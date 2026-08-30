//
//  LibraryClassifierQueryBuilder.swift
//  Salty
//
//  Builds the classifier-editor list query: every category/course/tag row of one classifier,
//  with the number of recipes using it, optionally narrowed by a search pattern and ordered by
//  either column in either direction.
//
//  Kept free of view-model state so the generated SQL can be unit-tested in isolation (see
//  LibraryClassifierQueryBuilderTests): `fragment(...).prepare { _ in "?" }.sql` yields the string.
//

import Foundation
import SQLiteData

/// Which column the classifier editor sorts by. The direction travels separately, so the macOS
/// table can flip either column from its header; the iOS sort menu exposes only the two
/// combinations that read well in a menu (see `LibraryClassifierSortOrder`).
public enum LibraryClassifierSortColumn: String, CaseIterable, Sendable {
    case name
    case recipeCount
}

/// The iOS sort menu's vocabulary: the two column-and-direction pairings the menu offers, each
/// mapped onto `LibraryClassifierSortColumn` + ascending for the query. (macOS has no menu -- the
/// table's column headers drive the same two properties directly.)
public enum LibraryClassifierSortOrder: String, CaseIterable, Identifiable, Sendable {
    /// A-Z, case-insensitive. The default: the list is something you scan for a known name.
    case name
    /// Most-used first, ties broken by name -- which also floats the unused rows to the bottom.
    case mostUsed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .name: return "Name"
        case .mostUsed: return "Most Used"
        }
    }

    public var column: LibraryClassifierSortColumn {
        switch self {
        case .name: return .name
        case .mostUsed: return .recipeCount
        }
    }

    public var ascending: Bool {
        self == .name
    }
}

public enum LibraryClassifierQueryBuilder {

    /// The full statement, ready for `$items.load`.
    public static func statement(
        classifier: LibraryClassifier,
        searchPattern: String?,
        column: LibraryClassifierSortColumn,
        ascending: Bool
    ) -> SQLQueryExpression<LibraryClassifierItem> {
        SQLQueryExpression(
            fragment(classifier: classifier, searchPattern: searchPattern, column: column, ascending: ascending),
            as: LibraryClassifierItem.self
        )
    }

    /// The raw query fragment (exposed for testing the generated SQL).
    ///
    /// - Parameter searchPattern: already wrapped in LIKE wildcards (e.g. `"%dess%"`), or nil for all rows.
    public static func fragment(
        classifier: LibraryClassifier,
        searchPattern: String?,
        column: LibraryClassifierSortColumn,
        ascending: Bool
    ) -> QueryFragment {
        let table = classifier.tableName

        // Column order MUST match LibraryClassifierItem's stored-property order -- the raw-SQL decoder
        // reads columns positionally. COUNT(DISTINCT …) so a junction table that already holds a
        // repeated (recipe, classifier) pair doesn't inflate the count, matching LibraryDuplicateMerger.
        var sql: QueryFragment = """
            SELECT "\(raw: table)"."id", IFNULL("\(raw: table)"."name", '') AS "name", \
            \(usageCount(classifier)) AS "recipeCount" FROM "\(raw: table)"
            """

        if let searchPattern {
            sql = "\(sql) WHERE \"\(raw: table)\".\"name\" COLLATE NOCASE LIKE \(bind: searchPattern)"
        }

        let direction = ascending ? "ASC" : "DESC"
        switch column {
        case .name:
            sql = "\(sql) ORDER BY \"name\" COLLATE NOCASE \(raw: direction)"
        case .recipeCount:
            // Name is always the tie-break, ascending, so equal counts stay scannable.
            sql = "\(sql) ORDER BY \"recipeCount\" \(raw: direction), \"name\" COLLATE NOCASE ASC"
        }
        return sql
    }

    /// The correlated subquery counting the recipes that reference one row.
    private static func usageCount(_ classifier: LibraryClassifier) -> QueryFragment {
        switch classifier {
        case .category:
            return #"(SELECT COUNT(DISTINCT "recipeId") FROM "recipeCategory" WHERE "categoryId" = "category"."id")"#
        case .tag:
            return #"(SELECT COUNT(DISTINCT "recipeId") FROM "recipeTag" WHERE "tagId" = "tag"."id")"#
        case .course:
            // A recipe holds at most one course, so there's nothing to de-duplicate.
            return #"(SELECT COUNT(*) FROM "recipe" WHERE "courseId" = "course"."id")"#
        }
    }
}
