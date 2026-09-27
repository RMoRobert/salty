//
//  RecipeWriter.swift
//  SaltyCore
//
//  The one place a user edit to a recipe is written, and therefore the one place the three sync
//  timestamps are stamped (see the comments on `Recipe` in Schema.swift):
//
//    lastModifiedDate          bumped on body edits, and on nothing else
//    lastModifiedImageDate     bumped only when the image changes, so a text edit never re-transfers
//                              the photo and a photo change never re-transfers the text
//    lastModifiedPreparedDate  bumped only when `lastPrepared` changes, so cooking something doesn't
//                              shove it to the top of the "Date Modified" sort
//
//  `save(_:in:)` decides which stamps a write earns by diffing against the row already stored.
//
//  NOT for the sync layer: writes that apply server state carry the *server's* timestamps and must
//  land byte-for-byte, so they use their own SQL.
//
//  Takes a `GRDB.Database` so callers supply the transaction and nothing here needs the main actor.
//

import Foundation
import GRDB
import SQLiteData

public enum RecipeWriter {

    /// What `save(_:in:)` decided to stamp. Returned so callers (and tests) can see the decision
    /// rather than infer it.
    public struct SaveOutcome: Equatable, Sendable {
        /// The recipe as written, including any timestamps this function set.
        public var recipe: Recipe
        /// Whether the row was inserted rather than updated.
        public var inserted: Bool
        /// Whether a field other than the image, `lastPrepared` and the three stamps changed.
        public var bodyChanged: Bool
        /// Whether `imageFilename` or `imageThumbnailData` changed.
        public var imageChanged: Bool
        /// Whether `lastPrepared` changed.
        public var preparedChanged: Bool
    }

    /// Inserts or updates `recipe`, stamping whichever of the three sync timestamps the change earns.
    ///
    /// A brand-new recipe (no row with this id yet) is inserted with `lastModifiedDate` set to `now`;
    /// its image and prepared stamps are left exactly as given, because a recipe created with a photo
    /// already carries the stamp the image writer set.
    ///
    /// For an existing row each stamp is decided by comparing against what is stored:
    ///
    /// - `lastModifiedDate` moves to `now` when any body field differs, and otherwise keeps the stored
    ///   value — so saving an unchanged recipe is not a modification, and an image-only save doesn't
    ///   reorder the "Date Modified" sort.
    /// - `lastModifiedImageDate` moves to `now` when the image differs, **or** when the caller has
    ///   already raised it above the stored value: a replaced photo usually keeps its `<recipeId>.<ext>`
    ///   filename, so the image writer's own stamp is honoured rather than trusting a thumbnail diff.
    /// - `lastModifiedPreparedDate` follows the same shape for `lastPrepared`. In practice "last made"
    ///   is written by `RecipeLastPreparedWriter` in its own targeted UPDATE and never arrives here.
    ///
    /// Stamps are never lowered: a value already ahead of `now` is left where it is, so a clock that
    /// steps backwards can't make a local edit look older than what the server already has.
    ///
    /// - Parameters:
    ///   - recipe: the edited recipe. Its own timestamp values are treated as a floor, never as the
    ///     answer.
    ///   - db: the transaction to write in.
    ///   - now: the stamp to apply. Injectable for tests; leave it alone in app code.
    /// - Returns: what was written and why.
    @discardableResult
    public static func save(_ recipe: Recipe, in db: Database, now rawNow: Date = Date()) throws -> SaveOutcome {
        // DATE-009: truncate to whole milliseconds at the source. The database drops sub-millisecond
        // precision and the wire format rounds it, so an unrounded stamp handed back from here could
        // be a millisecond off the row actually stored.
        let now = rawNow.roundedToWireMillis
        guard let stored = try Recipe.where({ $0.id.eq(recipe.id) }).fetchOne(db) else {
            var inserting = recipe
            inserting.lastModifiedDate = now
            try Recipe.insert { inserting }.execute(db)
            return SaveOutcome(recipe: inserting, inserted: true, bodyChanged: true,
                               imageChanged: inserting.imageFilename != nil,
                               preparedChanged: inserting.lastPrepared != nil)
        }

        let bodyChanged = bodyFingerprint(recipe) != bodyFingerprint(stored)
            || !sameInstant(recipe.createdDate, stored.createdDate)
        let imageChanged = recipe.imageFilename != stored.imageFilename
            || recipe.imageThumbnailData != stored.imageThumbnailData
        let preparedChanged = !sameInstant(recipe.lastPrepared, stored.lastPrepared)

        var writing = recipe
        writing.lastModifiedDate = bodyChanged
            ? raised(stored.lastModifiedDate, to: now)
            : stored.lastModifiedDate
        writing.lastModifiedImageDate = stamp(
            incoming: recipe.lastModifiedImageDate, stored: stored.lastModifiedImageDate,
            changed: imageChanged, now: now
        )
        writing.lastModifiedPreparedDate = stamp(
            incoming: recipe.lastModifiedPreparedDate, stored: stored.lastModifiedPreparedDate,
            changed: preparedChanged, now: now
        )

        try Recipe.update(writing).execute(db)
        return SaveOutcome(recipe: writing, inserted: false, bodyChanged: bodyChanged,
                           imageChanged: imageChanged, preparedChanged: preparedChanged)
    }

    /// Saves an edit to the recipe's body and nothing else: the photo and "last made" are kept exactly
    /// as they are stored now, whatever `edited` carries for them.
    ///
    /// For an editor holding an older copy: a photo or "made it" that arrived since (sync, another
    /// window) would otherwise be written back and stamped as new, spreading the revert to every device.
    /// A course deleted meanwhile becomes "no course" rather than failing the foreign key.
    ///
    /// An update, never an insert: throws `RecipeWriterError.recipeNotFound` if the recipe is gone.
    @discardableResult
    public static func saveBody(_ edited: Recipe, in db: Database, now: Date = Date()) throws -> SaveOutcome {
        guard let stored = try Recipe.where({ $0.id.eq(edited.id) }).fetchOne(db) else {
            throw RecipeWriterError.recipeNotFound(edited.id)
        }
        var merged = edited
        merged.imageFilename = stored.imageFilename
        merged.imageThumbnailData = stored.imageThumbnailData
        merged.lastModifiedImageDate = stored.lastModifiedImageDate
        merged.lastPrepared = stored.lastPrepared
        merged.lastModifiedPreparedDate = stored.lastModifiedPreparedDate
        merged.courseId = try existingCourseId(merged.courseId, in: db)
        return try save(merged, in: db, now: now)
    }

    /// Inserts a recipe that came from elsewhere (a `.saltyRecipe` file, a web page) as a change made
    /// here, now.
    ///
    /// `createdDate` and `lastPrepared` are kept. `lastModifiedDate`, and `lastModifiedPreparedDate` when
    /// there is a `lastPrepared`, are stamped now: a stamp from the file could predate the last sync and
    /// never upload. Image fields are dropped; attach the photo with `RecipeImageWriter`. An unknown
    /// `courseId` becomes nil.
    ///
    /// Throws if the id is already taken; mint a fresh one for each import.
    @discardableResult
    public static func insertImported(_ recipe: Recipe, in db: Database, now rawNow: Date = Date()) throws -> Recipe {
        let now = rawNow.roundedToWireMillis
        var inserting = recipe
        inserting.lastModifiedDate = now
        inserting.lastModifiedPreparedDate = recipe.lastPrepared == nil ? nil : now
        inserting.imageFilename = nil
        inserting.imageThumbnailData = nil
        inserting.lastModifiedImageDate = nil
        inserting.courseId = try existingCourseId(inserting.courseId, in: db)
        try Recipe.insert { inserting }.execute(db)
        return inserting
    }

    /// `courseId` if that course exists, else nil (a blank id is nil too).
    private static func existingCourseId(_ courseId: String?, in db: Database) throws -> String? {
        guard let courseId, !courseId.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return try Course.where({ $0.id.eq(courseId) }).fetchOne(db) == nil ? nil : courseId
    }

    // MARK: - Stamping rules

    /// One optional stamp's new value.
    ///
    /// Bumps to `now` when the thing it tracks changed, or when the caller has already moved it ahead
    /// of the stored value (see `save(_:in:)` on why the caller gets the last word). Otherwise the
    /// stored value stands, so an unrelated edit leaves it untouched.
    private static func stamp(incoming: Date?, stored: Date?, changed: Bool, now: Date) -> Date? {
        // "Ahead of", not merely "greater than": the two sides can be the same instant at different
        // precisions (see `sameInstant`), and a raw `>` would read that as a deliberate raise.
        let callerRaised = (incoming ?? .distantPast).timeIntervalSinceReferenceDate
            - (stored ?? .distantPast).timeIntervalSinceReferenceDate >= storageResolution
        guard changed || callerRaised else { return stored }
        return raised(max(stored ?? .distantPast, incoming ?? .distantPast), to: now)
    }

    /// The finest difference between two instants the database can actually represent: it stores dates
    /// as "yyyy-MM-dd HH:mm:ss.SSS".
    private static let storageResolution: TimeInterval = 0.001

    /// Whether two instants are the same as far as storage is concerned. An in-memory `Date()` carries
    /// sub-millisecond precision that SQLite drops, so a recipe and the row just written from it could
    /// otherwise compare unequal and bump `lastModifiedDate` for nothing.
    ///
    /// A tolerance rather than rounding both sides: rounding and truncation disagree at the millisecond
    /// boundary, and which one the storage layer does is an implementation detail.
    private static func sameInstant(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate) < storageResolution
    }

    private static func sameInstant(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): sameInstant(lhs, rhs)
        default: false
        }
    }

    /// `now`, unless `existing` is already later — stamps only ever move forwards.
    private static func raised(_ existing: Date, to now: Date) -> Date {
        max(existing, now)
    }

    /// The recipe with its stamps, image and "last made" flattened, so `==` answers "did the body
    /// change?". Built from the whole record rather than a field list so a new `Recipe` column is
    /// compared by default.
    private static func bodyFingerprint(_ recipe: Recipe) -> Recipe {
        var flattened = recipe
        flattened.lastModifiedDate = .distantPast
        flattened.lastModifiedImageDate = nil
        flattened.lastModifiedPreparedDate = nil
        flattened.lastPrepared = nil
        flattened.imageFilename = nil
        flattened.imageThumbnailData = nil
        // `createdDate` is the one date left, and dates can't be compared by `==` across a storage
        // round trip — `save` compares it separately with `sameInstant`.
        flattened.createdDate = .distantPast
        return flattened
    }
}
