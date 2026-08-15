//
//  LibraryDuplicateFinder.swift
//  Salty
//
//  The "which library rows share a name" half of the Consolidate Duplicates command: pure grouping
//  logic over `(id, name, recipeCount)` triples, with no database access, so it can be unit-tested
//  directly (see LibraryDuplicateTests). `LibraryDuplicateMerger` supplies the rows and performs the
//  merge the groups describe.
//

import Foundation

/// Which of the three name-only library tables a duplicate group belongs to. All three behave
/// identically for de-duplication purposes; they differ only in how recipes reference them
/// (`recipeCategory` / `recipeTag` junction rows vs. `recipe.courseId`).
public enum LibraryItemKind: String, CaseIterable, Identifiable, Sendable {
    case category
    case course
    case tag

    public var id: String { rawValue }

    public var singularLabel: String {
        switch self {
        case .category: return "Category"
        case .course: return "Course"
        case .tag: return "Tag"
        }
    }

    public var pluralLabel: String {
        switch self {
        case .category: return "Categories"
        case .course: return "Courses"
        case .tag: return "Tags"
        }
    }

    /// Matches the icons the sidebar uses for these rows.
    public var systemImage: String {
        switch self {
        case .category: return "rectangle.stack"
        case .course: return "fork.knife"
        case .tag: return "tag"
        }
    }
}

/// One category / course / tag row, with how many recipes currently reference it.
public struct LibraryDuplicateItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let recipeCount: Int

    public init(id: String, name: String, recipeCount: Int) {
        self.id = id
        self.name = name
        self.recipeCount = recipeCount
    }
}

/// A set of rows of one kind that share a name: the one to keep, and the ones to fold into it.
public struct LibraryDuplicateGroup: Identifiable, Hashable, Sendable {
    public let kind: LibraryItemKind
    /// The row that survives the merge. Its exact name -- including capitalization and spacing -- is
    /// the one that remains.
    public let survivor: LibraryDuplicateItem
    /// The rows whose recipes are re-pointed at `survivor` and which are then deleted. Ordered the
    /// same way survivors are chosen (most recipes first, then oldest).
    public let duplicates: [LibraryDuplicateItem]

    public var id: String { "\(kind.rawValue)_\(survivor.id)" }
    public var name: String { survivor.name }

    /// How many rows this group removes.
    public var removedCount: Int { duplicates.count }

    public init(kind: LibraryItemKind, survivor: LibraryDuplicateItem, duplicates: [LibraryDuplicateItem]) {
        self.kind = kind
        self.survivor = survivor
        self.duplicates = duplicates
    }
}

public enum LibraryDuplicateFinder {

    /// Which row of a same-named set is kept.
    public enum SurvivorRule: Sendable {
        /// The row the most recipes already use, ties to the oldest. Fewest junction rows to rewrite,
        /// so this is what the user-facing Consolidate Duplicates command uses.
        case mostRecipes
        /// The oldest row (smallest id), regardless of use. Recipe counts differ from device to
        /// device, so only an id-based rule makes two devices choose the *same* winner -- which is
        /// what the automatic post-sync pass needs in order to converge instead of ping-ponging.
        case oldestId
    }

    /// Groups rows of one kind by name, returning only names held by more than one row.
    ///
    /// Names are matched case-insensitively, ignoring leading/trailing whitespace and treating any
    /// run of internal whitespace as a single space -- so "Main dish", "Main  Dish" and " main dish "
    /// are one group. Rows whose name is empty (or whitespace only) are skipped rather than merged
    /// together: they carry no evidence of being the same thing.
    ///
    /// The survivor is the row with the most recipes; ties go to the oldest row. Ids are UUIDv7, so
    /// the smallest id is the earliest-created one (ignoring early Salty versions), and for any other id scheme,
    /// string order at least keeps the choice stable from run to run.
    ///
    /// Groups come back ordered by name (localized, case-insensitive).
    public static func groups(
        kind: LibraryItemKind,
        items: [LibraryDuplicateItem],
        rule: SurvivorRule = .mostRecipes
    ) -> [LibraryDuplicateGroup] {
        var buckets: [String: [LibraryDuplicateItem]] = [:]
        for item in items {
            let key = normalizedName(item.name)
            guard !key.isEmpty else { continue }
            buckets[key, default: []].append(item)
        }

        return buckets.values
            .filter { $0.count > 1 }
            .map { bucket in
                let ranked = bucket.sorted { lhs, rhs in
                    switch rule {
                    case .mostRecipes:
                        return lhs.recipeCount == rhs.recipeCount
                            ? lhs.id < rhs.id
                            : lhs.recipeCount > rhs.recipeCount
                    case .oldestId:
                        return lhs.id < rhs.id
                    }
                }
                return LibraryDuplicateGroup(kind: kind, survivor: ranked[0], duplicates: Array(ranked.dropFirst()))
            }
            .sorted {
                let byName = $0.name.localizedStandardCompare($1.name)
                return byName == .orderedSame ? $0.id < $1.id : byName == .orderedAscending
            }
    }

    /// The key two names are grouped by: case-folded, trimmed, internal whitespace collapsed.
    public static func normalizedName(_ name: String) -> String {
        name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
