//
//  AppDatabase.swift
//  Salty
//
//  Opens the app's database. Split from SaltyCore's Schema.swift because *where* the file lives is an
//  app concern -- the live path comes from a user-granted, security-scoped folder (see FileHelper) and
//  the preview/test paths come from the dependency context. The schema, migrations and repair passes
//  it applies are all SaltyCore's; this function only decides which file to open and in what order to
//  run them.
//

import Foundation
import SQLiteData
import GRDB
import OSLog
import SaltyCore

private let logger = Logger(subsystem: "Salty", category: "Database")

/// The connection settings every library is opened with.
private func libraryConfiguration() -> Configuration {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    // Wait out a competing writer (e.g., other app pointed at the same shared folder)
    // instead of failing fast with SQLITE_BUSY (GRDB's default busyMode is .immediateError).
    // Users should try to avoid in first place, but this helps with many outright failures.
    configuration.busyMode = .timeout(5)
    configuration.prepareDatabase { db in
#if DEBUG
        db.trace(options: .profile) {
            logger.debug("\($0.expandedDescription)")
        }
#endif
    }
    return configuration
}

/// Brings an open library up to date: both migrators, then the repair passes. Shared by the app's own
/// connection and by `checkLibrary(atPath:)`.
private func prepareLibrary(_ database: any DatabaseWriter) throws {
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
}

/// Creates (or opens and migrates) the library at `path`, then closes it again: a check that a newly
/// chosen folder can hold a library, made before the app is pointed at it. Touches no app state, so
/// it can run off the main actor; the caller must already hold any security scope the folder needs.
nonisolated func checkLibrary(atPath path: String) throws {
    let queue = try DatabaseQueue(path: path, configuration: libraryConfiguration())
    try prepareLibrary(queue)
    try queue.close()
}

func appDatabase() throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    let database: any DatabaseWriter
    let configuration = libraryConfiguration()
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
    try prepareLibrary(database)

#if DEBUG
    if context == .preview {
      try database.write { db in
        try db.seedSampleData()
      }
    }
#endif

    return database
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
