//
//  Schema.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SQLiteData
import GRDB
import OSLog
import Foundation
import UUIDV7

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: "Salty", category: "Database")

// Record Types

@Table("recipe")
struct Recipe: Codable, Hashable, Identifiable, Equatable, TableRecord  {
    var id: String
    var name: String = ""
    var createdDate: Date = Date()
    var lastModifiedDate: Date = Date()
    var lastPrepared: Date?
    var source: String = ""
    var sourceDetails: String = ""
    var introduction: String = ""
    var difficulty: Difficulty = .notSet
    var rating: Rating = .notSet
    var imageFilename: String?
    var imageThumbnailData: Data?
    // Bumped ONLY when the image changes (set/replaced/removed), independent of lastModifiedDate, so a
    // text-only edit never re-transfers the image and an image-only edit never re-transfers the body.
    // Owned by the image-sync pass; appended at the end of the table via a shared migration.
    var lastModifiedImageDate: Date?
    var isFavorite: Bool = false
    var wantToMake: Bool = false
    var yield: String = ""
    var servings: Int?
    var courseId: String?
    @Column(as: [Direction].JSONRepresentation.self)
    var directions: [Direction] = []
    @Column(as: [Ingredient].JSONRepresentation.self)
    var ingredients: [Ingredient] = []
    @Column(as: [Note].JSONRepresentation.self)
    var notes: [Note] = []
    @Column(as: [Variation].JSONRepresentation.self)
    var variations: [Variation] = []
    @Column(as: [PreparationTime].JSONRepresentation.self)
    var preparationTimes: [PreparationTime] = []
    @Column(as: NutritionInformation?.JSONRepresentation.self)
    var nutrition: NutritionInformation? = nil
    
    var summary: String {
        return (
            introduction != "" ? introduction : (
                source != "" ? source : (
                    sourceDetails != "" ? sourceDetails : ""
                )
            )
        )
    }
    
    //    var categories: [Category]?
    //    var tags: [Tag]?
}


//
//extension Recipe {
//    enum Columns {
//        static let id = Column(CodingKeys.id)
//        static let name = Column(CodingKeys.name)
//        static let createdDate = Column(CodingKeys.createdDate)
//        static let lastModifedDate = Column(CodingKeys.lastModifiedDate)
//        static let lastPrepared = Column(CodingKeys.lastPrepared)
//        static let source = Column(CodingKeys.source)
//        static let sourceDetails = Column(CodingKeys.sourceDetails)
//        static let introduction = Column(CodingKeys.introduction)
//        static let difficulty = Column(CodingKeys.difficulty)
//        static let rating = Column(CodingKeys.rating)
//        static let imageFilename = Column(CodingKeys.imageFilename)
//        static let imageThumbnailData = Column(CodingKeys.imageThumbnailData)
//        static let isFavorite = Column(CodingKeys.isFavorite)
//        static let wantToMake = Column(CodingKeys.wantToMake)
//        static let yield = Column(CodingKeys.yield)
//        static let servings = Column(CodingKeys.servings)
//        static let courseId = Column(CodingKeys.courseId)
//        static let directions = JSONColumn(CodingKeys.directions)
//        static let ingredients = JSONColumn(CodingKeys.ingredients)
//        static let notes  = JSONColumn(CodingKeys.notes)
//        static let preparationTimes = JSONColumn(CodingKeys.preparationTimes)
//        static let nutrition = JSONColumn(CodingKeys.nutrition)
//    }
//    
//    static var databaseSelection: [any SQLSelectable] {
//        [Columns.id, Columns.name, Columns.createdDate, Columns.lastModifedDate,
//         Columns.source, Columns.sourceDetails, Columns.introduction,
//         Columns.difficulty, Columns.rating, Columns.imageFilename,
//         Columns.imageThumbnailData, Columns.lastPrepared, Columns.isFavorite, Columns.wantToMake,
//         Columns.yield, Columns.servings, Columns.courseId,
//         Database.json(Columns.directions), Database.json(Columns.ingredients),
//         Database.json(Columns.notes), Database.json(Columns.preparationTimes),
//         Database.json(Columns.nutrition)]
//    }
//}

// MARK: - Recipe Image Extensions

extension Recipe {
    /// Loads the full image data from external storage
    var fullImageData: Data? {
        guard let filename = imageFilename else { return nil }
        return RecipeImageManager.shared.loadImage(filename: filename)
    }
    
    /// Gets the URL for the full image from external storage
    var fullImageURL: URL? {
        guard let filename = imageFilename else { return nil }
        return FileManager.saltyImageFolderUrl.appending(component: filename)
    }
    
    /// Sets the image data, saving to external storage and generating thumbnail
    mutating func setImage(_ imageData: Data?) {
        if let imageData = imageData {
            if let result = RecipeImageManager.shared.saveImage(imageData, for: id) {
                self.imageFilename = result.filename
                self.imageThumbnailData = result.thumbnailData
                self.lastModifiedImageDate = Date() // Image-only change: bump the image date, NOT lastModifiedDate
            }
        } else {
            // Remove existing image
            if let filename = imageFilename {
                RecipeImageManager.shared.deleteImage(filename: filename)
            }
            self.imageFilename = nil
            self.imageThumbnailData = nil
            self.lastModifiedImageDate = Date() // Image-only change (removal): bump the image date only
        }
    }

    /// Removes the image and cleans up external storage
    mutating func removeImage() {
        if let filename = imageFilename {
            RecipeImageManager.shared.deleteImage(filename: filename)
        }
        self.imageFilename = nil
        self.imageThumbnailData = nil
        self.lastModifiedImageDate = Date() // Image-only change (removal): bump the image date only
    }
    
    /// Bumps lastModifiedDate so sync propagates changes to recipe relationships or metadata.
    /// Updates ONLY the timestamp column — a full-row `Recipe.update` would re-write `courseId`, which
    /// fails the `courseId → course` FK if that recipe carries a dangling course reference (introduced
    /// by the FK-less server or a peer app that didn't enforce the constraint). GRDB stores Date in the
    /// same "yyyy-MM-dd HH:mm:ss.SSS" UTC format as the rest of the schema.
    static func touchLastModified(recipeId: String, in db: Database) throws {
        try db.execute(
            sql: #"UPDATE "recipe" SET "lastModifiedDate" = ? WHERE "id" = ?"#,
            arguments: [Date(), recipeId],
        )
    }
    
    static func touchLastModified(recipeIds: some Sequence<String>, in db: Database) throws {
        for recipeId in Set(recipeIds) {
            try touchLastModified(recipeId: recipeId, in: db)
        }
    }
}

/// Lightweight projection of `recipe` for the main list. Rows render only name/summary/rating/favorite/
/// thumbnail (plus created/modified dates in the info popover), so fetching this instead of a full
/// `Recipe` avoids decoding the ingredients/directions/notes/variations/preparationTimes/nutrition JSON
/// blobs for every row. Full rows are fetched on demand (detail view, edit, export, print, share) via
/// `RecipeNavigationSplitViewModel.fullRecipe(id:)`.
///
/// IMPORTANT: the SELECT column order in `RecipeListQueryBuilder` must match the stored-property order
/// below — the raw-SQL decoder reads columns positionally. `lastModifiedDate` and `imageThumbnailData`
/// are included so that any edit (body edits bump `lastModifiedDate`; image edits change the thumbnail)
/// changes this projection and therefore refreshes the observing list/detail.
@Selection
struct RecipeListItem: Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    let source: String
    let sourceDetails: String
    let introduction: String
    let createdDate: Date
    let lastModifiedDate: Date
    let rating: Rating
    let isFavorite: Bool
    let imageThumbnailData: Data?
}

extension RecipeListItem {
    /// Mirrors `Recipe.summary` — the best available one-line subtitle.
    var summary: String {
        introduction != "" ? introduction : (source != "" ? source : (sourceDetails != "" ? sourceDetails : ""))
    }

    /// Project an in-memory `Recipe` (used for previews and the preview view model).
    init(recipe r: Recipe) {
        self.init(
            id: r.id, name: r.name, source: r.source, sourceDetails: r.sourceDetails,
            introduction: r.introduction, createdDate: r.createdDate, lastModifiedDate: r.lastModifiedDate,
            rating: r.rating, isFavorite: r.isFavorite, imageThumbnailData: r.imageThumbnailData
        )
    }
}


struct Note: Codable, Hashable, Equatable, Identifiable {
    var id: String
    var title: String
    var content: String
}

struct Variation: Codable, Hashable, Equatable, Identifiable {
    var id: String
    var variationName: String
    var text: String
}

@Table("course")
struct Course: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var lastModifiedDate: Date?
}
//
//extension Course: FetchableRecord, PersistableRecord {
//    enum Columns {
//        static let id = Column(CodingKeys.id)
//        static let name = Column(CodingKeys.name)
//    }
//    
//    static var databaseSelection: [any SQLSelectable] {
//        [Columns.id, Columns.name]
//    }
//}

struct Direction: Codable, Hashable, Equatable, Identifiable  {
    var id: String
    var isHeading: Bool?
    var text: String
}

struct Ingredient: Codable, Hashable, Equatable, Identifiable  {
    var id: String
    var isHeading: Bool = false
    var isMain: Bool = false
    var text: String
}

struct PreparationTime: Codable, Hashable, Equatable, Identifiable  {
    var id: String
    var type: String
    var timeString: String
}

struct NutritionInformation: Codable, Hashable, Equatable, Identifiable {
    var id: String = UUIDV7().uuidString
    var servingSize: String? = nil
    var calories: Double? = nil
    var protein: Double? = nil // grams
    var carbohydrates: Double? = nil // grams
    var fat: Double? = nil // grams
    var saturatedFat: Double? = nil // grams
    var transFat: Double? = nil // grams
    var fiber: Double? = nil // grams
    var sugar: Double? = nil // grams
    var sodium: Double? = nil // milligrams
    var cholesterol: Double? = nil // milligrams
    var addedSugar: Double? = nil // grams
    var vitaminD: Double? = nil // micrograms
    var calcium: Double? = nil // milligrams
    var iron: Double? = nil // milligrams
    var potassium: Double? = nil // milligrams
    var vitaminA: Double? = nil // micrograms
    var vitaminC: Double? = nil // milligrams
}

@Table("category")
struct Category: Hashable, Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var lastModifiedDate: Date?
}

@Table("tag")
struct Tag: Hashable, Identifiable, Codable, Equatable, TableRecord {
    var id: String
    var name: String
    var lastModifiedDate: Date?
}

enum Difficulty: Int, Codable, CaseIterable, QueryBindable {
    case notSet = 0,  easy, somewhatEasy, medium, slightlyDifficult, difficult
    
    // for use with SwiftUI sliders:
    init(index: Double = 0) {
        if let type = Self.allCases.first(where: { $0.asIndex == index }) {
            self = type
        } else {
            self = .notSet
        }
    }
    var asIndex: Double {
        return Double(self.rawValue)
    }
    
    var id:  Int {
        return self.rawValue
    }
    
    func stringValue() -> String {
        switch(self) {
        case .notSet:
            return "(not set)"
        case .easy:
            return "easy"
        case .somewhatEasy:
            return "somewhat easy"
        case .medium:
            return "medium"
        case .slightlyDifficult:
            return "slightly difficult"
        case .difficult:
            return "difficult"
        }
    }
}

enum Rating: Int, CaseIterable, Identifiable, Codable, QueryBindable {
    case notSet = 0, one, two, three, four, five
    
    // for use with SwiftUI sliders:
    init(index: Double = 0) {
        if let type = Self.allCases.first(where: { $0.asIndex == index }) {
            self = type
        } else {
            self = .notSet
        }
    }
    
    var id: Int {
        return self.rawValue
    }
    
    var asIndex: Double {
        return Double(self.rawValue)
    }
    
    func stringValue() -> String {
        switch(self) {
        case .notSet:
            return "not set"
        case .one:
            return "1"
        case .two:
            return "2"
        case .three:
            return "3"
        case .four:
            return "4"
        case .five:
            return "5"
        }
    }
}


// Junction tables

@Table("recipeCategory")
struct RecipeCategory:  Codable, Hashable, Equatable, PersistableRecord, FetchableRecord {
    var id: String
    var recipeId: String
    var categoryId: String
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let recipeId = Column(CodingKeys.recipeId)
        static let categoryId = Column(CodingKeys.categoryId)
    }
    
    static var databaseSelection: [any SQLSelectable] {
        [Columns.id, Columns.recipeId, Columns.categoryId]
    }
}

@Table("recipeTag")
struct RecipeTag:  Codable, Hashable, Equatable, PersistableRecord, FetchableRecord {
    var id: String
    var recipeId: String
    var tagId: String
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let recipeId = Column(CodingKeys.recipeId)
        static let tagId = Column(CodingKeys.tagId)
        
        static let tag = belongsTo(Tag.self)
        static let recipe = belongsTo(Recipe.self)
    }
    
    static var databaseSelection: [any SQLSelectable] {
        [Columns.id, Columns.recipeId, Columns.tagId]
    }
}

@Table("shoppingList")
struct ShoppingList: Hashable, Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var isFreeform: Bool
    var contentsForFreeform: String?
    @Column(as: [ShoppingListListContents].JSONRepresentation.self)
    var contentsForList: [ShoppingListListContents] = []
    // Appended at the end of the table (shared migration) so positional SELECT * keeps working if in use anywhere in any app
    var lastModifiedDate: Date?
    // Sync version owned entirely by sync layer (UI edit paths never set), so ditry data detected
    // as row vs. snapshot, not tracked by Swift (or Kotlin) clients: server revision this row was last synced
    // at, plus a snapshot of the `ServerShoppingList` JSON at that time (so can do three-way merge if needed).
    // Column added at end as above to preserve positional SELECT * queries.
    var syncedRevision: Int64?
    var syncedSnapshot: String?
}

struct ShoppingListListContents: Codable, Hashable, Equatable, Identifiable  {
    var id: String
    var isCompleted: Bool? = false
    var isImportant: Bool? = false
    // Optional so rows written before headings existed still decode (nil == non-heading).
    var isHeading: Bool? = false
    var text: String
}


// DatabaseWriter code, migrations, etc:

func appDatabase() throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    let database: any DatabaseWriter
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    configuration.prepareDatabase { db in
#if DEBUG
        db.trace(options: .profile) {
            logger.debug("\($0.expandedDescription)")
        }
#endif
    }
    if context == .preview {
        database = try DatabaseQueue(configuration: configuration)
    } else {
        // For a custom (security-scoped) location, begin and hold access BEFORE opening the
        // connection so the long-lived DatabasePool — and its -wal/-shm files — stay reachable.
        if context == .live {
            FileManager.beginAccessingDatabaseLocation()
        }
        let path =
         context == .live
        ? FileManager.saltyLibraryFullPath.path
        : URL.temporaryDirectory.appending(component: "\(UUID().uuidString)-saltyLibrary.sqlite").path()
        logger.info("open \(path)")
        database = try DatabasePool(path: path, configuration: configuration)
    }
    // These GRDB migrations coordinate the BASE tables across both apps. SaltyKMP mirrors their
    // identifiers in `GRDB_MIGRATIONS` (shared/.../db/Database.kt) and seeds them into `grdb_migrations`
    // on a KMP-created DB so this migrator skips them. If you add a new base migration ("0005…") here,
    // add the SAME identifier to KMP's `GRDB_MIGRATIONS`. For changes BOTH apps need on EXISTING shared
    // tables, prefer the `saltyMigration` ledger (`saltySharedMigrations` below) instead of a new GRDB
    // migration, so KMP applies it too.
    let migrator = saltyMigrator()
    logger.info("Starting database migration...")
    try migrator.migrate(database)
    logger.info("Database migration completed successfully")

    // Cross-platform shared migrations. GRDB's migrator (grdb_migrations) and SaltyKMP's SQLDelight
    // migrator (PRAGMA user_version) only coordinate the BASE tables; for any later change BOTH apps
    // need on the shared saltyRecipeDB.sqlite, the `saltyMigration` ledger is the single source of truth
    // so it runs exactly once, whoever opens the file first. Mirror of SaltyKMP's applySharedMigrations.
    try runSaltySharedMigrations(database)

    // Defensive: the shared DB may be written by SaltyKMP or raw SQL, which can leave non-optional
    // `recipe` columns NULL. GRDB would then fail to decode the row (JSON columns and Dates can't be
    // nil), making the recipe unopenable. Runs every launch and only touches offending rows.
    coalesceNullRecipeColumns(database)
    // Same for `shoppingList` — plus it backfills the nullable `lastModifiedDate`, which a future
    // sync would otherwise read as `distantPast` and delete the list instead of uploading it.
    coalesceNullShoppingListColumns(database)

#if DEBUG
    if context == .preview {
      try database.write { db in
        try db.seedSampleData()
      }
    }
#endif

    return database
}

/// Builds the GRDB migrator for the base tables (0001-0004), extracted from `appDatabase()` so the
/// migrations can be applied to a test database in isolation. SaltyKMP mirrors these identifiers (see the
/// note in `appDatabase()`); keep new base migrations idempotent so a KMP-seeded DB that already has a
/// column can re-run them safely.
func saltyMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
#if DEBUG
    migrator.eraseDatabaseOnSchemaChange = false
#endif
    migrator.registerMigration("0001: Create initial tables") { db in
        logger.info("Running 'Create initial tables' migration")

        try db.create(table: "course") { t in
            t.primaryKey("id", .text, onConflict: .replace).notNull().defaults(to: UUIDV7().uuidString)
            t.column("name", .text)
            t.column("lastModifiedDate", .datetime)
        }
        
        try db.create(table: "category") { t in
            t.primaryKey("id", .text, onConflict: .replace).notNull().defaults(to: UUIDV7().uuidString)
            t.column("name", .text)
            t.column("lastModifiedDate", .datetime)
        }
        
        try db.create(table: "recipe") { t in
            t.primaryKey("id", .text, onConflict: .replace).notNull().defaults(to: UUIDV7().uuidString)
            t.column("name", .text).notNull()
            t.column("createdDate", .datetime)
            t.column("lastModifiedDate", .datetime)
            t.column("lastPrepared", .datetime)
            t.column("source", .text)
            t.column("sourceDetails", .text)
            t.column("introduction", .text)
            t.column("difficulty", .integer)
            t.column("rating", .integer)
            t.column("imageFilename", .text)
            t.column("imageThumbnailData", .blob)
            t.column("isFavorite", .boolean)
            t.column("wantToMake", .boolean)
            t.column("yield", .text)
            t.column("servings", .integer)
            t.column("courseId", .text).references("course", onDelete: .setNull)
            t.column("directions", .jsonText)
            t.column("ingredients", .jsonText)
            t.column("notes", .jsonText)
            t.column("preparationTimes", .jsonText)
            t.column("nutrition", .jsonText)
        }
        
        try db.create(table: "recipeCategory") { t in
            t.primaryKey("id", .text, onConflict: .replace).notNull().defaults(to: UUIDV7().uuidString)
            t.column("recipeId", .text).notNull().indexed().references("recipe", onDelete: .cascade)
            t.column("categoryId", .text).notNull().indexed().references("category", onDelete: .cascade)
        }
        
        try db.create(table: "tag") { t in
            t.primaryKey("id", .text, onConflict: .replace).notNull().defaults(to: UUIDV7().uuidString)
            t.column("name", .text)
            t.column("lastModifiedDate", .datetime)
        }
        
        try db.create(table: "recipeTag") { t in
            t.primaryKey("id", .text, onConflict: .replace).notNull().defaults(to: UUIDV7().uuidString)
            t.column("recipeId", .text).notNull().indexed().references("recipe", onDelete: .cascade)
            t.column("tagId", .text).notNull().indexed().references("tag", onDelete: .cascade)
        }
        
        try db.create(table: "shoppingList") { t in
            t.primaryKey("id", .text, onConflict: .replace).notNull().defaults(to: UUIDV7().uuidString)
            t.column("name", .text)
            t.column("isFreeform", .boolean)
            t.column("contentsForList", .jsonText)
            t.column("contentsForFreeform", .text)
        }
    }
    
    // NOTE: the identifier still says "and shopping lists" but no longer seeds one — the app now starts
    // with no lists and offers to create one. The identifier itself must NOT be edited: it's recorded in
    // `grdb_migrations` (renaming would re-run this on every existing DB and duplicate the categories and
    // courses) and mirrored in SaltyKMP's `GRDB_MIGRATIONS`. Databases created before this change keep
    // the default list they were seeded with, which is intentional — this is not a data migration.
    migrator.registerMigration("0002: Populate default categories, courses, and shopping lists") { db in
        logger.info("Running 'Populate default categories and courses' migration")

        // Add default category names to database
        let defaultCategories = [
            "Breads", "Breakfast", "Soups", "Pasta", "Holiday"
            //, "Quick", "Vegetarian",  "Beverage"   // <- considered and could do; skipping as demo recieps have nothing for these categories
        ]
        for categoryName in defaultCategories {
            let category = Category(id: UUIDV7().uuidString, name: categoryName)
            try Category.insert { category }.execute(db)
        }
        
        // Add default course names to database
        let defaultCourses = [
            "Appetizer", "Main", "Dessert", "Snack", "Salad", "Fruit", "Cheese", "Vegetable",
            "Side Dish", "Bread", "Sauce"
        ]
        for courseName in defaultCourses {
            let course = Course(id: UUIDV7().uuidString, name: courseName)
            try Course.insert { course }.execute(db)
        }
    }
    
    migrator.registerMigration("0003: Add 'variations' column to 'recipe' table") { db in
        logger.info("Running '0003: Add variations column...' migration")
        // Idempotent (like 0004): a KMP-created DB may already have this column from its Schema.sq while
        // this migration isn't yet recorded in grdb_migrations — guard on existence so re-applying can't
        // fail with "duplicate column name: variations".
        let hasColumn = (try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM pragma_table_info('recipe') WHERE name = 'variations'"
        ) ?? 0) > 0
        if !hasColumn {
            try db.alter(table: "recipe") { t in
                t.add(column: "variations", .jsonText)
            }
        }
    }

    migrator.registerMigration("0004: Add 'lastModifiedDate' column to 'category', 'course', and 'tag' tables") { db in
        logger.info("Running '0004: Add lastModifiedDate column to category, course, and tag tables' migration")
        // Idempotent: 0001 now creates these columns on new installs; older DBs may still need this.
        func needsColumn(table: String) throws -> Bool {
            // pragma_table_info expects a string literal table name (single quotes), not a double-quoted identifier.
            let escaped = table.replacingOccurrences(of: "'", with: "''")
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info('\(escaped)') WHERE name = 'lastModifiedDate'"
            ) ?? 0
            return count == 0
        }
        if try needsColumn(table: "category") {
            try db.alter(table: "category") { t in
                t.add(column: "lastModifiedDate", .datetime)
            }
        }
        if try needsColumn(table: "course") {
            try db.alter(table: "course") { t in
                t.add(column: "lastModifiedDate", .datetime)
            }
        }
        if try needsColumn(table: "tag") {
            try db.alter(table: "tag") { t in
                t.add(column: "lastModifiedDate", .datetime)
            }
        }
    }
    
      // Example of what additional future migrations could look like in future (do not use this example verbatim--already part of schema):
//    migrator.registerMigration("0010: Convert to single course per recipe") { db in
//        // Add column
//        try db.alter(table: "recipe") { t in
//            t.add(column: "courseId", .text).references("course", onDelete: .setNull)
//        }
//        // Drop table
//        try db.drop(table: "recipeCourse")
//    }

    return migrator
}

/// Backfills NULLs in `recipe` columns that the Swift model treats as non-optional, so a row authored by
/// another writer (SaltyKMP, a raw `INSERT`, an older import) still decodes. Best-effort and idempotent:
/// each `UPDATE` only matches rows that are actually NULL, so re-running is a cheap no-op. The
/// genuinely-optional columns (`lastPrepared`, `image*`, `servings`, `courseId`, `nutrition`,
/// `lastModifiedImageDate`) are intentionally left alone. `difficulty`/`rating` coalesce to 0 (`.notSet`).
///
/// NOTE: this repairs existing rows but does not prevent future NULL writes. SaltyKMP's `Schema.sq` now
/// declares these columns `NOT NULL DEFAULT` (mirroring this set) so fresh shared DBs enforce the
/// invariant; this pass stays as the cross-platform safety net for older DBs and raw writers.
func coalesceNullRecipeColumns(_ writer: any DatabaseWriter) {
    // Each group maps a SQL substitution to the columns that should never be NULL in a decodable row.
    let substitutions: [(value: String, columns: [String])] = [
        ("'[]'", ["directions", "ingredients", "notes", "variations", "preparationTimes"]),
        ("''", ["name", "source", "sourceDetails", "introduction", "yield"]),
        ("0", ["isFavorite", "wantToMake", "difficulty", "rating"]),
        ("CURRENT_TIMESTAMP", ["createdDate", "lastModifiedDate"]),
    ]
    do {
        try writer.write { db in
            for (value, columns) in substitutions {
                for column in columns {
                    try db.execute(sql: #"UPDATE "recipe" SET "\#(column)" = \#(value) WHERE "\#(column)" IS NULL"#)
                }
            }
        }
    } catch {
        logger.error("Recipe NULL-coalescing pass failed: \(error.localizedDescription)")
    }
}

/// The `shoppingList` counterpart to `coalesceNullRecipeColumns`, repairing NULLs that either break
/// decoding or, once shopping lists join sync, silently destroy a list. Same contract: best-effort,
/// idempotent (each `UPDATE` matches only offending rows), runs on every open.
///
/// Two distinct hazards are covered:
///
/// 1. **Decodability.** `name`, `isFreeform`, and `contentsForList` are non-optional on the Swift
///    model but nullable in SQL (migration 0001, and SaltyKMP's `Schema.sq` likewise), so a row
///    written by KMP or raw SQL can fail to decode — taking the whole list-of-lists fetch with it,
///    not just that row.
/// 2. **Sync safety.** `lastModifiedDate` is nullable and only arrived in `SHARED-V0002`, so rows
///    predating it — and anything KMP writes until it mirrors that migration — are NULL. The sync
///    reconciler maps a missing timestamp to `Date.distantPast`, which is ALWAYS `<= lastSyncDate`,
///    so such a row takes the `toDeleteLocally` branch: **deleted instead of uploaded** on its first
///    sync. Coalescing to "now" biases the other way (treated as recently modified → uploaded),
///    which is the non-destructive direction. This must stay in place before `shoppingList` is added
///    to the sync set — see FEATURE_PLANS.md.
func coalesceNullShoppingListColumns(_ writer: any DatabaseWriter) {
    do {
        try writer.write { db in
            try db.execute(sql: #"UPDATE "shoppingList" SET "name" = '' WHERE "name" IS NULL"#)
            try db.execute(sql: #"UPDATE "shoppingList" SET "contentsForList" = '[]' WHERE "contentsForList" IS NULL"#)
            // Derive rather than defaulting to 0: a row carrying freeform text but a NULL flag would
            // otherwise open as an empty checklist, hiding content the user actually wrote.
            try db.execute(sql: #"""
                UPDATE "shoppingList"
                SET "isFreeform" = (CASE WHEN "contentsForFreeform" IS NOT NULL AND "contentsForFreeform" <> '' THEN 1 ELSE 0 END)
                WHERE "isFreeform" IS NULL
                """#)
            try db.execute(sql: #"UPDATE "shoppingList" SET "lastModifiedDate" = CURRENT_TIMESTAMP WHERE "lastModifiedDate" IS NULL"#)
        }
    } catch {
        logger.error("Shopping list NULL-coalescing pass failed: \(error.localizedDescription)")
    }
}

/// Flush the WAL into the main `.sqlite` so another app (SaltyKMP, syncing the linked folder) sees the
/// latest data in the *main* file — and leaves an empty WAL so the handoff is a single clean file.
/// Best-effort: if a reader still holds the WAL we fall back to a passive checkpoint, which never blocks.
/// Call when the app quiesces (background / terminate), not on every save.
func checkpointDatabaseForHandoff(_ writer: any DatabaseWriter) {
    do {
        try writer.writeWithoutTransaction { db in
            _ = try db.checkpoint(.truncate)
        }
    } catch {
        try? writer.writeWithoutTransaction { db in
            _ = try db.checkpoint(.passive)
        }
    }
}

// MARK: - Cross-platform shared migrations (the `saltyMigration` ledger)

/// A schema/data change that BOTH the Salty (GRDB) app and the SaltyKMP app must apply to a shared
/// `saltyRecipeDB.sqlite`. Coordinated via the `saltyMigration` table — NOT GRDB's `grdb_migrations` —
/// so it runs once per DB regardless of which app opens it first.
///
/// Keep this list in lockstep with SaltyKMP's `SHARED_MIGRATIONS`
/// (shared/src/commonMain/kotlin/com/inuvro/saltykmp/db/Database.kt), using the SAME `id` for a shared
/// change. Namespace platform-only steps ("swift:…" / "kmp:…") so the other side never references them.
/// Use `ADD COLUMN` and append columns at the end of the table (so the other platform's `SELECT *` keeps
/// working); the ledger provides run-once, so the SQL itself needn't be idempotent.
struct SaltySharedMigration: Sendable {
    let id: String
    let apply: @Sendable (GRDB.Database) throws -> Void
}

/// The shared migration list. Append future cross-app changes here AND in SaltyKMP's
/// `SHARED_MIGRATIONS` with the identical `id`. Example:
///
///     SaltySharedMigration(id: "SHARED-V0003") { db in
///         try db.execute(sql: #"ALTER TABLE "recipe" ADD COLUMN "prepNotes" TEXT"#)
///     }
///
/// **Identifier convention:** `SHARED-V####`, numbered in the order entries are added.
///   - An `id` is IMMUTABLE once it has shipped. It's the primary key of the `saltyMigration` ledger,
///     and that ledger is the only record of what has already run. Renaming a shipped id makes the
///     migration look unapplied — so the other app (or an older build of either app) re-runs it.
///   - The FIRST entry below predates this convention and keeps its date-style id, which is why
///     numbering starts at V0002. Don't "fix" it: see the point above.
///   - Execution order is this array's order, NOT the identifier. The numbers are a naming
///     convention for humans, nothing sorts by them.
///
/// Do NOT coordinate a shared-table change by adding a new GRDB `migrator.registerMigration("0005…")` —
/// that path only coordinates the BASE tables (0001-0004), and KMP wouldn't apply it. Shared changes go
/// through this ledger on BOTH apps.
let saltySharedMigrations: [SaltySharedMigration] = [
    // Decouples image transfer from recipe-body sync. Guard on column existence so this is safe whether the
    // column is already present (a KMP-created DB whose Schema.sq has it) or not (an older GRDB DB). Mirror:
    // SaltyKMP's SHARED_MIGRATIONS with the SAME id.
    SaltySharedMigration(id: "2026-06-recipe-add-lastModifiedImageDate") { db in
        let exists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM pragma_table_info('recipe') WHERE name = 'lastModifiedImageDate'"
        ) ?? 0 > 0
        if !exists {
            try db.execute(sql: #"ALTER TABLE "recipe" ADD COLUMN "lastModifiedImageDate" DATETIME"#)
        }
    },
    // Sync-readiness for shopping lists (see FEATURE_PLANS.md cross-cutting notes): every mutable table
    // gets a lastModifiedDate. Mirror: SaltyKMP DB's SHARED_MIGRATIONS with same id ("SHARED-V0002").
    // This is the ONLY place the column is added — deliberately not also in migration 0001. `shoppingList`
    // is a shared table, so a GRDB-only migration would never run on a KMP-created database, and editing
    // 0001 wouldn't reach databases that already recorded it. The ledger covers all three cases (fresh,
    // pre-existing, KMP-created) through one code path, with no chance of the two definitions drifting.
    SaltySharedMigration(id: "SHARED-V0002") { db in
        let exists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM pragma_table_info('shoppingList') WHERE name = 'lastModifiedDate'"
        ) ?? 0 > 0
        if !exists {
            try db.execute(sql: #"ALTER TABLE "shoppingList" ADD COLUMN "lastModifiedDate" DATETIME"#)
        }
    },
    // Revision-based shopping-list sync (see salty_kmp/SHOPPING_LIST_REVISIONS_PLAN.md): the server
    // revision each row was last agreed at, plus the wire-JSON snapshot of that agreement (the
    // three-way merge base). Guarded per column so it's safe whether a KMP-created DB already has
    // them or not. Mirror: SaltyKMP's SHARED_MIGRATIONS with the SAME id ("SHARED-V0003").
    SaltySharedMigration(id: "SHARED-V0003") { db in
        let revisionExists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM pragma_table_info('shoppingList') WHERE name = 'syncedRevision'"
        ) ?? 0 > 0
        if !revisionExists {
            try db.execute(sql: #"ALTER TABLE "shoppingList" ADD COLUMN "syncedRevision" INTEGER"#)
        }
        let snapshotExists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM pragma_table_info('shoppingList') WHERE name = 'syncedSnapshot'"
        ) ?? 0 > 0
        if !snapshotExists {
            try db.execute(sql: #"ALTER TABLE "shoppingList" ADD COLUMN "syncedSnapshot" TEXT"#)
        }
    }
]

/// Applies any shared migrations not yet recorded in `saltyMigration`, then records them (platform
/// `swift`). Idempotent and cheap, so it runs on every launch — catching migrations added after a DB
/// already existed and ones the KMP app recorded but this app hasn't seen. `migrations` is injectable
/// for tests.
func runSaltySharedMigrations(
    _ writer: any DatabaseWriter,
    _ migrations: [SaltySharedMigration] = saltySharedMigrations
) throws {
    let appliedDate: String = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }()
    try writer.write { db in
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS "saltyMigration" (
                "identifier" TEXT NOT NULL PRIMARY KEY,
                "platform" TEXT,
                "appliedDate" TEXT NOT NULL
            )
            """)
        for migration in migrations {
            let alreadyApplied = try Int.fetchOne(
                db,
                sql: #"SELECT 1 FROM "saltyMigration" WHERE "identifier" = ?"#,
                arguments: [migration.id]
            ) != nil
            if alreadyApplied { continue }
            logger.info("Running shared migration: \(migration.id)")
            try migration.apply(db)
            try db.execute(
                sql: #"INSERT OR IGNORE INTO "saltyMigration" ("identifier", "platform", "appliedDate") VALUES (?, 'swift', ?)"#,
                arguments: [migration.id, appliedDate]
            )
        }
    }
}


#if DEBUG
extension Database {
    func seedSampleData() throws {
        try seed {
            for category in SampleData.sampleCategories {
                category
            }
            for course in SampleData.sampleCourses {
                course
            }
            for tag in SampleData.sampleTags {
                tag
            }
            for recipe in SampleData.sampleRecipes {
                recipe
            }
            for shoppingList in SampleData.sampleShoppingLists {
                shoppingList
            }
        }
    }
}
#endif
