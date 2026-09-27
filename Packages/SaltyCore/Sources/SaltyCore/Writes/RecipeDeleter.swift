//
//  RecipeDeleter.swift
//  SaltyCore
//
//  Deleting recipes on purpose: the rows, their category and tag links, and a tombstone each, so the
//  next sync deletes them on the server rather than taking them back as rows this device never had.
//
//  Not for the sync layer, which applies deletions that came FROM the server and must not tombstone them.
//

import Foundation
import GRDB

public enum RecipeDeleter {

    /// Deletes the recipes in `ids` that exist, inside the caller's transaction, and returns the image
    /// filenames they referenced.
    ///
    /// The files are the caller's to remove, and only after the transaction commits: a file that outlives
    /// its row is an orphan, while a row that outlives its file is a broken image on every device. See
    /// `RecipeImageWriter.deleteFiles(forRecipe:except:imagesDirectory:)`.
    @discardableResult
    public static func delete(ids: some Sequence<String>, in db: Database) throws -> (deletedIds: [String], imageFilenames: [String]) {
        let wanted = Array(Set(ids.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }))
        guard !wanted.isEmpty else { return ([], []) }

        let marks = databaseQuestionMarks(count: wanted.count)
        let arguments = StatementArguments(wanted)
        // Raw rows rather than `Recipe`: a recipe whose JSON can't be decoded must still be deletable.
        let rows = try Row.fetchAll(db, sql: #"SELECT "id", "imageFilename" FROM "recipe" WHERE "id" IN (\#(marks))"#, arguments: arguments)
        let existing: [String] = rows.map { $0["id"] }
        guard !existing.isEmpty else { return ([], []) }
        let filenames: [String] = rows.compactMap { $0["imageFilename"] }

        let existingMarks = databaseQuestionMarks(count: existing.count)
        let existingArguments = StatementArguments(existing)
        // The links go with the row through ON DELETE CASCADE when foreign keys are on; said outright so
        // it holds on a connection where they aren't.
        try db.execute(sql: #"DELETE FROM "recipeCategory" WHERE "recipeId" IN (\#(existingMarks))"#, arguments: existingArguments)
        try db.execute(sql: #"DELETE FROM "recipeTag" WHERE "recipeId" IN (\#(existingMarks))"#, arguments: existingArguments)
        try db.execute(sql: #"DELETE FROM "recipe" WHERE "id" IN (\#(existingMarks))"#, arguments: existingArguments)
        try RecipeTombstoneWriter.recordDeletions(existing, in: db)
        return (existing, filenames)
    }
}
