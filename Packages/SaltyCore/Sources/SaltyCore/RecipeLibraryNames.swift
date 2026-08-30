//
//  RecipeLibraryNames.swift
//  Salty
//
//  Resolves a recipe's course / category / tag display names from the junction tables, for anywhere a
//  recipe needs its library associations as text (HTML export, the web detail view, JSON-LD export).
//

import Foundation
import SQLiteData
import GRDB

public struct RecipeLibraryNames: Sendable {
    public var course: String?
    public var categories: [String]
    public var tags: [String]

    public init(course: String?, categories: [String], tags: [String]) {
        self.course = course
        self.categories = categories
        self.tags = tags
    }

    public static let empty = RecipeLibraryNames(course: nil, categories: [], tags: [])
}

extension Recipe {
    /// Best-effort resolution of this recipe's course/category/tag names (sorted, case-insensitive).
    /// Returns empty names if the read fails.
    public func libraryNames(database: any DatabaseReader) -> RecipeLibraryNames {
        let recipeId = id
        let courseId = courseId
        return (try? database.read { db in
            let course = try courseId.flatMap { cid in
                try Course.where { $0.id.eq(cid) }.fetchOne(db)?.name
            }
            let categoryIds = try RecipeCategory.where { $0.recipeId.eq(recipeId) }.fetchAll(db).map(\.categoryId)
            let categories = try Category.where { categoryIds.contains($0.id) }.fetchAll(db)
                .map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let tagIds = try RecipeTag.where { $0.recipeId.eq(recipeId) }.fetchAll(db).map(\.tagId)
            let tags = try Tag.where { tagIds.contains($0.id) }.fetchAll(db)
                .map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return RecipeLibraryNames(course: course, categories: categories, tags: tags)
        }) ?? .empty
    }
}
