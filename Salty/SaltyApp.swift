//
//  SaltyApp.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import OSLog
import SQLiteData
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct SaltyApp: App {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    /// The live database writer, kept so we can checkpoint its WAL when the app quiesces (so SaltyKMP,
    /// syncing the linked folder, sees the latest data in the main `.sqlite`). Nil in non-live contexts.
    private let database: (any DatabaseWriter)?

    init() {
        // Locals (not stored properties): init must not touch `self` until `database` is assigned below.
        let logger = Logger(subsystem: "Salty", category: "App")
        @Dependency(\.context) var context

        var createdDatabase: (any DatabaseWriter)? = nil
        if context == .live {
            do {
                // Begin (and hold) security-scoped access to the database location before opening it.
                FileManager.beginAccessingDatabaseLocation()

                // Validate access; if a custom location can't be reached, try one fresh resolution.
                if !FileManager.validateDatabaseAccess() {
                    logger.error("Warning: Database access validation failed. Attempting to re-resolve location bookmark...")
                    if FileManager.refreshCustomDatabaseBookmark() {
                        logger.debug("Successfully re-resolved database location bookmark")
                    } else {
                        logger.error("Failed to re-resolve database location - may need user intervention")
                    }
                }

                let db = try Salty.appDatabase()
                createdDatabase = db
                prepareDependencies {
                    $0.defaultDatabase = db
                }

#if os(macOS)
                // Cmd-Q doesn't reliably drive scenePhase → checkpoint on terminate so the handoff file is current.
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification, object: nil, queue: .main
                ) { [db] _ in
                    checkpointDatabaseForHandoff(db)
                }
#endif

                // Create backup after successful database initialization
                let backupManager = DatabaseBackupManager()
                backupManager.createBackupIfNeeded()
            } catch {
                // Log the error but don't crash the app
                logger.error("Failed to initialize database: \(error)")
            }
        }
        self.database = createdDatabase
    }
    
    var body: some Scene {
        // Main window; the id lets File ▸ New Window open another one (see Menus.swift)
        WindowGroup(id: "main-window") {
            MainView()
                .handlesExternalEvents(preferring: ["salty-recipe"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["salty-recipe"])
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // iOS: fires on background. (macOS quit handled by the willTerminate observer in init.)
                if let database { checkpointDatabaseForHandoff(database) }
                AutoSyncCoordinator.shared.appWillBackground()
            case .active:
                // Launch / return-to-foreground: pull server-side changes if auto-sync is on (throttled).
                Task { await AutoSyncCoordinator.shared.appBecameActive() }
            default:
                break
            }
        }
        .commands {
            Menus()
        }
        
        // "Edit Categories" window
        WindowGroup(id: "edit-categories-window") {
            LibraryCategoriesEditView()
                .frame(idealWidth: 250)
                .navigationTitle("Categories Editor")
        }
        // "Edit Tags" window
        WindowGroup(id: "edit-tags-window") {
            LibraryTagsEditView()
                .frame(idealWidth: 250)
                .navigationTitle("Tags Editor")
        }
        // "Edit Courses" window
        WindowGroup(id: "edit-courses-window") {
            LibraryCoursesEditView()
                .frame(idealWidth: 250)
                .navigationTitle("Courses Editor")
        }
        // "Show Duplicate Recipes" window (File ▸ Library; a sheet on iOS)
        WindowGroup(id: "duplicate-recipes-window") {
            NavigationStack {
                DuplicateRecipesView()
            }
            .frame(minWidth: 420, idealWidth: 640, minHeight: 400, idealHeight: 600)
        }
        // "Consolidate Duplicate Categories, Courses, and Tags" window (File ▸ Library; a sheet on iOS)
        WindowGroup(id: "consolidate-duplicates-window") {
            NavigationStack {
                ConsolidateDuplicatesView()
            }
            .frame(minWidth: 420, idealWidth: 620, minHeight: 360, idealHeight: 520)
        }
        // "Open Database" window
        WindowGroup(id: "open-database-window") {
            OpenDBView()
                #if os(macOS)
                .frame(minWidth: 300, minHeight: 400)
                #endif
                .navigationTitle("Open Database")
        }

        // "Import from Web" window
        WindowGroup(id: "create-recipe-from-web-window") {
            CreateRecipeFromWebView()
                .frame(idealWidth: 800)
                .navigationTitle("Import Recipe from Web")
        }
        // "Import from Image" window
        WindowGroup(id: "create-recipe-from-image-window") {
            CreateRecipeFromImageView()
                .frame(idealWidth: 800)
                .navigationTitle("Import Recipe from Image")
        }

        #if os(macOS)
        // Standalone recipe viewer (narrow split views → open full detail in its own window)
        WindowGroup(id: "recipe-detail-window", for: String.self) { $recipeId in
            NavigationStack {
                RecipeDetailWindowView(recipeId: $recipeId)
            }
            .frame(minWidth: 520, idealWidth: 720, minHeight: 420, idealHeight: 680)
        }
        .defaultSize(width: 720, height: 680)

        Settings {
            SettingsView()
        }
        #endif
    }
}

func isLiquidGlassAvailable() -> Bool {
    if #available(iOS 26.0, macOS 26.0, *) {
        return true
    }
    else {
        return false
    }
}
