//
//  LibraryClassifier.swift
//  Salty
//  Created by Robert 8/18/2026
//
//  "Classifier" is the internal name for the three database tables a recipe can be filed
//  under: categories, courses, and tags. They differ only in how recipes reference them
//  (`recipeCategory`/`recipeTag` junction rows vs. `recipe.courseId`), but otherwise,
//  this helps everything that treats them similarly -- the editor, the duplicate finder,
//  recipe importers' name resolvers -- write once against this enum instead of three
//  separate things.
//

import Foundation
import SQLiteData

public enum LibraryClassifier: String, CaseIterable, Identifiable, Sendable {
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

    /// The table the rows live in.
    public var tableName: String {
        switch self {
        case .category: return "category"
        case .course: return "course"
        case .tag: return "tag"
        }
    }
}

/// One category / course / tag row, with how many recipes currently reference it.
///
/// IMPORTANT: the SELECT column order in `LibraryClassifierQueryBuilder` must match the stored-property
/// order below -- the raw-SQL decoder reads columns positionally. `recipeCount` is part of the
/// projection so that adding or removing a recipe's classification refreshes the observing editor list.
@Selection
public struct LibraryClassifierItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let recipeCount: Int

    public init(id: String, name: String, recipeCount: Int) {
        self.id = id
        self.name = name
        self.recipeCount = recipeCount
    }
}
