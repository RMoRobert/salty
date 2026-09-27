//
//  LibraryWritesTests.swift
//  SaltyTests
//
//  SaltyCore/Writes beyond `RecipeWriter.save`: body-only saves, imports, deletes, photos, and
//  categories/tags. Each pins a rule sync depends on: which clock moves, what gets a tombstone, which
//  file outlives which row.
//
//  Same harness and the same raw-SQL rule as RecipeWriterTests: StructuredQueries builders crash when
//  instantiated from the test bundle, so rows are seeded and read back by hand.
//

import Testing
import Foundation
import GRDB
import SaltyCore

struct LibraryWritesTests {

    // MARK: - Harness

    private func library() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try saltyMigrator().migrate(queue)
        try runSaltySharedMigrations(queue)
        return queue
    }

    private func storedRecipe(in queue: DatabaseQueue, at stamp: Date, configure: (inout Recipe) -> Void = { _ in }) throws -> Recipe {
        var recipe = Recipe(id: SaltyId.new(), name: "Sourdough")
        configure(&recipe)
        return try queue.write { db in try RecipeWriter.save(recipe, in: db, now: stamp).recipe }
    }

    private func row(_ id: String, from queue: DatabaseQueue) throws -> Row? {
        try queue.read { db in try Row.fetchOne(db, sql: #"SELECT * FROM "recipe" WHERE "id" = ?"#, arguments: [id]) }
    }

    private func count(_ sql: String, _ arguments: StatementArguments = [], in queue: DatabaseQueue) throws -> Int {
        try queue.read { db in try Int.fetchOne(db, sql: sql, arguments: arguments) ?? -1 }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "salty-writes-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private let past = Date(timeIntervalSince1970: 1_000_000)
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let later = Date(timeIntervalSince1970: 3_000_000)

    // MARK: - saveBody

    /// The editor's copy predates a photo and a "made it" that arrived since; saving its text must not
    /// put the old values back.
    @Test func aBodySaveKeepsThePhotoAndLastMadeAsStored() throws {
        let queue = try library()
        let original = try storedRecipe(in: queue, at: past)
        // Meanwhile: a photo and a "made it" land.
        var updated = original
        updated.imageFilename = "\(original.id).jpg"
        updated.imageThumbnailData = Data([1, 2, 3])
        updated.lastPrepared = now
        _ = try queue.write { db in try RecipeWriter.save(updated, in: db, now: now) }

        var edited = original
        edited.name = "Better Sourdough"
        let saved = try queue.write { db in try RecipeWriter.saveBody(edited, in: db, now: later) }

        #expect(saved.bodyChanged)
        let stored = try #require(try row(original.id, from: queue))
        #expect(stored["name"] == "Better Sourdough")
        #expect(stored["imageFilename"] == "\(original.id).jpg")
        #expect((stored["imageThumbnailData"] as Data?) == Data([1, 2, 3]))
        #expect((stored["lastPrepared"] as Date?) != nil)
        #expect(saved.imageChanged == false, "the photo wasn't touched, so its clock mustn't move")
    }

    @Test func aBodySaveNamingACourseThatIsGoneLandsAsNoCourse() throws {
        let queue = try library()
        let original = try storedRecipe(in: queue, at: past)
        var edited = original
        edited.courseId = "course-deleted-elsewhere"

        _ = try queue.write { db in try RecipeWriter.saveBody(edited, in: db, now: now) }

        #expect((try #require(try row(original.id, from: queue))["courseId"] as String?) == nil)
    }

    @Test func aBodySaveOfARecipeThatIsGoneThrows() throws {
        let queue = try library()
        let ghost = Recipe(id: SaltyId.new(), name: "Gone")
        #expect(throws: RecipeWriterError.recipeNotFound(ghost.id)) {
            try queue.write { db in try RecipeWriter.saveBody(ghost, in: db, now: now) }
        }
    }

    // MARK: - insertImported

    @Test func anImportIsStampedAsAChangeMadeNowButKeepsItsHistory() throws {
        let queue = try library()
        var imported = Recipe(id: SaltyId.new(), name: "From a file")
        imported.createdDate = past
        imported.lastModifiedDate = past
        imported.lastPrepared = past
        imported.imageFilename = "stale.jpg"
        imported.courseId = "no-such-course"

        let stored = try queue.write { db in try RecipeWriter.insertImported(imported, in: db, now: now) }

        #expect(stored.lastModifiedDate == now)
        #expect(stored.lastModifiedPreparedDate == now, "a carried lastPrepared gets its own stamp")
        #expect(stored.createdDate == past)
        #expect(stored.lastPrepared == past)
        #expect(stored.imageFilename == nil, "the photo is attached separately, with its own stamp")
        #expect(stored.courseId == nil)
        #expect(try row(imported.id, from: queue) != nil)
    }

    // MARK: - RecipeDeleter

    @Test func deletingRecipesTombstonesThemAndReturnsTheirPhotos() throws {
        let queue = try library()
        let withPhoto = try storedRecipe(in: queue, at: past) { $0.imageFilename = "\($0.id).jpg" }
        let plain = try storedRecipe(in: queue, at: past)
        try queue.write { db in
            try db.execute(sql: #"INSERT INTO "category" ("id", "name") VALUES ('cat-1', 'Breads')"#)
            try db.execute(sql: #"INSERT INTO "recipeCategory" ("id", "recipeId", "categoryId") VALUES ('rc-1', ?, 'cat-1')"#,
                           arguments: [withPhoto.id])
        }

        let result = try queue.write { db in
            try RecipeDeleter.delete(ids: [withPhoto.id, plain.id, "never-existed"], in: db)
        }

        #expect(Set(result.deletedIds) == [withPhoto.id, plain.id])
        #expect(result.imageFilenames == ["\(withPhoto.id).jpg"])
        #expect(try count(#"SELECT COUNT(*) FROM "recipe""#, in: queue) == 0)
        #expect(try count(#"SELECT COUNT(*) FROM "recipeCategory""#, in: queue) == 0)
        let tombstones = try queue.read { db in try RecipeTombstoneWriter.pending(in: db) }
        #expect(Set(tombstones) == [withPhoto.id, plain.id], "only recipes that existed are tombstoned")
    }

    // MARK: - RecipeImageWriter

    @Test func settingAPhotoWritesTheFileAndMovesOnlyTheImageClock() throws {
        let queue = try library()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recipe = try storedRecipe(in: queue, at: past)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])

        let saved = try queue.write { db in
            try RecipeImageWriter.setImage(png, fileExtension: "jpg", thumbnail: Data([9]), forRecipe: recipe.id,
                                           imagesDirectory: directory, in: db, now: now)
        }

        #expect(saved.imageFilename == "\(recipe.id).png", "the extension comes from the bytes")
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "\(recipe.id).png").path(percentEncoded: false)))
        #expect(saved.lastModifiedImageDate == now)
        #expect(saved.lastModifiedDate == recipe.lastModifiedDate, "a photo isn't a text edit")
        #expect(saved.imageThumbnailData == Data([9]))
    }

    @Test func clearingAPhotoStampsTheRemovalAndOldFilesCanThenGo() throws {
        let queue = try library()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recipe = try storedRecipe(in: queue, at: past)
        _ = try queue.write { db in
            try RecipeImageWriter.setImage(Data([0xFF, 0xD8, 0xFF, 0xE0]), thumbnail: nil, forRecipe: recipe.id,
                                           imagesDirectory: directory, in: db, now: now)
        }
        try Data([1]).write(to: directory.appending(path: "\(recipe.id).heic")) // a stray

        let cleared = try queue.write { db in try RecipeImageWriter.clearImage(forRecipe: recipe.id, in: db, now: later) }
        RecipeImageWriter.deleteFiles(forRecipe: recipe.id, except: nil, imagesDirectory: directory)

        #expect(cleared.imageFilename == nil)
        #expect(cleared.lastModifiedImageDate == later, "a removal that didn't move the clock would be undone by sync")
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(left.isEmpty)
    }

    // MARK: - RecipeClassificationWriter

    @Test func replacingCategoriesAndTagsMovesTheRecipeClockOnlyWhenSomethingChanged() throws {
        let queue = try library()
        let recipe = try storedRecipe(in: queue, at: past)
        try queue.write { db in
            try db.execute(sql: #"INSERT INTO "category" ("id", "name") VALUES ('cat-a', 'A'), ('cat-b', 'B')"#)
            try db.execute(sql: #"INSERT INTO "tag" ("id", "name") VALUES ('tag-1', 'quick')"#)
        }

        let changed = try queue.write { db in
            try RecipeClassificationWriter.set(categoryIds: ["cat-a", "cat-b", "cat-missing"], tagIds: ["tag-1"],
                                               forRecipe: recipe.id, in: db, now: now)
        }
        #expect(changed)
        #expect(try count(#"SELECT COUNT(*) FROM "recipeCategory" WHERE "recipeId" = ?"#, [recipe.id], in: queue) == 2,
                "an id whose category is gone is skipped, not a failed foreign key")
        #expect((try #require(try row(recipe.id, from: queue))["lastModifiedDate"] as Date?) == now)

        let unchanged = try queue.write { db in
            try RecipeClassificationWriter.set(categoryIds: ["cat-b", "cat-a"], tagIds: nil, forRecipe: recipe.id, in: db, now: later)
        }
        #expect(!unchanged, "the same set in another order is no change")
        #expect((try #require(try row(recipe.id, from: queue))["lastModifiedDate"] as Date?) == now)

        try queue.write { db in
            try RecipeClassificationWriter.set(categoryIds: ["cat-a"], tagIds: [], forRecipe: recipe.id, in: db, now: later)
        }
        #expect(try count(#"SELECT COUNT(*) FROM "recipeCategory" WHERE "recipeId" = ?"#, [recipe.id], in: queue) == 1)
        #expect(try count(#"SELECT COUNT(*) FROM "recipeTag" WHERE "recipeId" = ?"#, [recipe.id], in: queue) == 0)
    }

    @Test func aLinkToACategoryThatIsGoneIsKeptWhenAskedFor() throws {
        let queue = try library()
        let recipe = try storedRecipe(in: queue, at: past)
        // Outside a transaction: SQLite ignores the foreign_keys pragma inside one.
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(sql: #"INSERT INTO "recipeCategory" ("id", "recipeId", "categoryId") VALUES ('rc-o', ?, 'cat-gone')"#,
                           arguments: [recipe.id])
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let changed = try queue.write { db in
            try RecipeClassificationWriter.set(categoryIds: ["cat-gone"], tagIds: nil, forRecipe: recipe.id, in: db, now: now)
        }

        #expect(!changed)
        #expect(try count(#"SELECT COUNT(*) FROM "recipeCategory" WHERE "categoryId" = 'cat-gone'"#, in: queue) == 1)
    }
}
