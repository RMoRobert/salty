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
