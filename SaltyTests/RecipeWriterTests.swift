//
//  RecipeWriterTests.swift
//  SaltyTests
//
//  `RecipeWriter.save`'s stamping rules. Sync compares exactly these columns: a missed bump is an
//  edit that never leaves the device, and a spurious one re-transfers the recipe (or, for
//  `lastModifiedDate`, reorders the "Date Modified" sort).
//
//  Rows are seeded and read back with raw SQL (or through the writer itself), never with a
//  StructuredQueries `.insert {}` / `.where {}` builder: those crash at runtime when instantiated
//  from the test bundle, missing protocol-witness symbols across the test-host boundary. The writers
//  under test use the builders from inside SaltyCore, where they resolve fine.
//

import Testing
import Foundation
import GRDB
import SaltyCore

struct RecipeWriterTests {

    // MARK: - Harness

    private func library() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try saltyMigrator().migrate(queue)
        // The image/prepared stamps (and `shoppingList.lastModifiedDate`) come from the shared
        // migrations, not the base schema.
        try runSaltySharedMigrations(queue)
        return queue
    }

    /// A recipe stored with known timestamps, so each test can assert on movement rather than values.
    /// Inserting through `save` stamps `lastModifiedDate` and keeps the image and prepared stamps as
    /// `configure` set them.
    private func storedRecipe(
        in queue: DatabaseQueue,
        at stamp: Date,
        configure: (inout Recipe) -> Void = { _ in }
    ) throws -> Recipe {
        var recipe = Recipe(id: SaltyId.new(), name: "Sourdough")
        recipe.ingredients = [Ingredient(id: SaltyId.new(), isHeading: false, isMain: true, text: "flour")]
        configure(&recipe)
        return try queue.write { db in try RecipeWriter.save(recipe, in: db, now: stamp).recipe }
    }

    /// The stored row for `id`, read with raw SQL. See the note at the top of the file.
    private func row(_ id: String, from queue: DatabaseQueue) throws -> Row {
        let found = try queue.read { db in
            try Row.fetchOne(db, sql: #"SELECT * FROM "recipe" WHERE "id" = ?"#, arguments: [id])
        }
        return try #require(found)
    }

    private func modified(_ id: String, in queue: DatabaseQueue) throws -> Date? {
        try row(id, from: queue)["lastModifiedDate"]
    }

    private func imageStamp(_ id: String, in queue: DatabaseQueue) throws -> Date? {
        try row(id, from: queue)["lastModifiedImageDate"]
    }

    private func preparedStamp(_ id: String, in queue: DatabaseQueue) throws -> Date? {
        try row(id, from: queue)["lastModifiedPreparedDate"]
    }

    private let past = Date(timeIntervalSince1970: 1_000_000)
    private let now = Date(timeIntervalSince1970: 2_000_000)

    // MARK: - lastModifiedDate

    @Test("a body edit bumps lastModifiedDate")
    func bodyEditBumpsModified() throws {
        let queue = try library()
        var recipe = try storedRecipe(in: queue, at: past)

        recipe.name = "Sourdough, revised"
        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.bodyChanged)
        #expect(try modified(recipe.id, in: queue) == now)
    }

    @Test("saving a recipe nothing changed on leaves lastModifiedDate where it was")
    func noChangeLeavesModifiedAlone() throws {
        let queue = try library()
        let recipe = try storedRecipe(in: queue, at: past)

        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.bodyChanged == false)
        #expect(try modified(recipe.id, in: queue) == past)
    }

    @Test("an image-only change does not bump lastModifiedDate")
    func imageOnlyChangeLeavesModifiedAlone() throws {
        let queue = try library()
        var recipe = try storedRecipe(in: queue, at: past)

        recipe.imageFilename = "\(recipe.id).jpg"
        recipe.imageThumbnailData = Data([0xFF, 0xD8, 0xFF, 0x01])
        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.imageChanged)
        #expect(outcome.bodyChanged == false)
        #expect(try modified(recipe.id, in: queue) == past)
        #expect(try imageStamp(recipe.id, in: queue) == now)
    }

    @Test("a text edit does not bump the image stamp, so the photo isn't re-transferred")
    func bodyEditLeavesImageStampAlone() throws {
        let queue = try library()
        var recipe = try storedRecipe(in: queue, at: past) { draft in
            draft.imageFilename = "photo.jpg"
            draft.imageThumbnailData = Data([0x01, 0x02])
            draft.lastModifiedImageDate = self.past
        }

        recipe.introduction = "A long ferment."
        try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(try modified(recipe.id, in: queue) == now)
        #expect(try imageStamp(recipe.id, in: queue) == past)
    }

    // MARK: - The caller's image stamp wins

    /// A replaced photo keeps its `<recipeId>.<ext>` filename, so if the thumbnail bytes also matched,
    /// a comparison-only rule would never sync the new full-size image.
    @Test("a stamp the image writer already raised is honoured even when the bytes look identical")
    func honoursCallerRaisedImageStamp() throws {
        let queue = try library()
        var recipe = try storedRecipe(in: queue, at: past) { draft in
            draft.imageFilename = "photo.jpg"
            draft.imageThumbnailData = Data([0x01, 0x02])
            draft.lastModifiedImageDate = self.past
        }

        // Same filename, same thumbnail bytes — only the caller's stamp says the image moved.
        recipe.lastModifiedImageDate = now.addingTimeInterval(-1)
        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.imageChanged == false)
        #expect(try imageStamp(recipe.id, in: queue) == now)
    }

    @Test("stamps only ever move forwards, so a clock that stepped back can't age a local edit")
    func stampsNeverGoBackwards() throws {
        let queue = try library()
        let future = Date(timeIntervalSince1970: 9_000_000)
        var recipe = try storedRecipe(in: queue, at: future)

        recipe.name = "Edited while the clock was wrong"
        try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(try modified(recipe.id, in: queue) == future)
    }

    // MARK: - lastPrepared

    @Test("changing lastPrepared bumps only the prepared stamp")
    func preparedChangeBumpsOnlyPreparedStamp() throws {
        let queue = try library()
        var recipe = try storedRecipe(in: queue, at: past)

        recipe.lastPrepared = Date(timeIntervalSince1970: 1_500_000)
        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.preparedChanged)
        #expect(outcome.bodyChanged == false)
        #expect(try modified(recipe.id, in: queue) == past)
        #expect(try preparedStamp(recipe.id, in: queue) == now)
    }

    // MARK: - Insert

    @Test("a recipe with no stored row is inserted and stamped as modified now")
    func insertsWhenAbsent() throws {
        let queue = try library()
        var recipe = Recipe(id: SaltyId.new(), name: "New")
        recipe.lastModifiedDate = past

        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.inserted)
        #expect(try modified(recipe.id, in: queue) == now)
    }

    @Test("a second save of the same recipe updates rather than failing on the primary key")
    func secondSaveUpdates() throws {
        let queue = try library()
        var recipe = Recipe(id: SaltyId.new(), name: "New")

        recipe = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: past).recipe }
        recipe.name = "Renamed"
        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.inserted == false)
        #expect(try row(recipe.id, from: queue)["name"] == "Renamed")
    }

    // MARK: - Storage precision

    /// SQLite drops sub-millisecond precision, so a recipe created this session and saved twice without
    /// a re-read must not compare as changed against its stored row.
    @Test("a recipe created in memory and saved twice isn't reported as modified the second time")
    func inMemoryDatePrecisionIsNotABodyChange() throws {
        let queue = try library()
        // Full-precision `Date()` for createdDate, exactly as a newly built draft carries.
        var recipe = Recipe(id: SaltyId.new(), name: "Imported", createdDate: Date())

        recipe = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: past).recipe }
        // Note: NOT re-read from the database — this is the in-memory copy the view model keeps.
        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.bodyChanged == false)
        #expect(try modified(recipe.id, in: queue) == past)
    }

    /// Deliberately a whole number of milliseconds plus a sliver, not a value sitting on a rounding
    /// boundary: the point is that a difference finer than storage can represent is not a change.
    @Test("a lastPrepared that only differs below a millisecond isn't a change")
    func subMillisecondPreparedDifferenceIsNotAChange() throws {
        let queue = try library()
        let cooked = Date(timeIntervalSince1970: 1_500_000.25)
        var recipe = try storedRecipe(in: queue, at: past) { $0.lastPrepared = cooked }

        recipe.lastPrepared = cooked.addingTimeInterval(0.0001)
        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.preparedChanged == false)
    }

    /// The counterpart: a real change to "last made" must still be seen.
    @Test("a lastPrepared that differs by more than a millisecond is a change")
    func realPreparedDifferenceIsAChange() throws {
        let queue = try library()
        let cooked = Date(timeIntervalSince1970: 1_500_000.25)
        var recipe = try storedRecipe(in: queue, at: past) { $0.lastPrepared = cooked }

        recipe.lastPrepared = cooked.addingTimeInterval(1)
        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(outcome.preparedChanged)
    }

    @Test("clearing lastPrepared is a change, and so is setting it from nothing")
    func preparedNilTransitionsAreChanges() throws {
        let queue = try library()
        let cooked = Date(timeIntervalSince1970: 1_500_000.25)
        var recipe = try storedRecipe(in: queue, at: past) { $0.lastPrepared = cooked }

        recipe.lastPrepared = nil
        let cleared = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }
        #expect(cleared.preparedChanged)

        var again = cleared.recipe
        again.lastPrepared = cooked
        let set = try queue.write { db in try RecipeWriter.save(again, in: db, now: now) }
        #expect(set.preparedChanged)
    }

    // MARK: - DATE-009

    /// DATE-009: a generated timestamp is truncated to whole milliseconds at the source. SQLite drops
    /// sub-millisecond precision while `SyncWireDate` rounds it, so an untruncated stamp could make the
    /// row handed back from a save differ from the row stored.
    @Test("a generated stamp is already whole milliseconds, so stored and returned agree")
    func generatedStampsAreWholeMilliseconds() throws {
        let queue = try library()
        var recipe = Recipe(id: SaltyId.new(), name: "Precision")

        // A `now` with deliberate sub-millisecond precision, as `Date()` always has.
        let messy = Date(timeIntervalSince1970: 1_700_000_000.1234567)
        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: messy) }

        let returned = try #require(outcome.recipe.lastModifiedDate)
        let stored = try #require(try modified(recipe.id, in: queue))
        #expect(returned == stored, "the row handed back must be the row stored")
        #expect(returned == returned.roundedToWireMillis, "the stamp should already be whole milliseconds")

        // And the round trip is stable: saving what came back is not an edit.
        recipe = outcome.recipe
        let again = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: messy) }
        #expect(again.bodyChanged == false)
        #expect(try modified(recipe.id, in: queue) == stored)
    }

    // MARK: - Coverage of the fingerprint

    /// The body diff covers the whole record, so these easily-missed JSON columns count by default.
    @Test("edits to the JSON-backed columns count as body changes", arguments: 0..<5)
    func jsonColumnsCountAsBodyChanges(which: Int) throws {
        let queue = try library()
        var recipe = try storedRecipe(in: queue, at: past)

        switch which {
        case 0: recipe.ingredients = [Ingredient(id: SaltyId.new(), isHeading: false, isMain: false, text: "salt")]
        case 1: recipe.directions = [Direction(id: SaltyId.new(), isHeading: false, text: "Mix.")]
        case 2: recipe.notes = [Note(id: SaltyId.new(), title: "Tip", content: "Rest it.")]
        case 3: recipe.variations = [Variation(id: SaltyId.new(), variationName: "Rye", text: "Swap flour.")]
        default: recipe.preparationTimes = [PreparationTime(id: SaltyId.new(), type: "Bake", timeString: "40 min")]
        }

        let outcome = try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }
        #expect(outcome.bodyChanged)
        #expect(try modified(recipe.id, in: queue) == now)
    }

    @Test("toggling a flag counts as a body change")
    func flagsCountAsBodyChanges() throws {
        let queue = try library()
        var recipe = try storedRecipe(in: queue, at: past)

        recipe.isFavorite.toggle()
        try queue.write { db in try RecipeWriter.save(recipe, in: db, now: now) }

        #expect(try modified(recipe.id, in: queue) == now)
    }
}
