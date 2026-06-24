//
//  SaltyApp.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import OSLog
import SQLiteData
import SwiftUI

@main
struct SaltyApp: App {
    private let logger = Logger(subsystem: "Salty", category: "App")
    @Dependency(\.context) var context
    @Environment(\.openWindow) private var openWindow
    
    init() {
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

                try prepareDependencies {
                    $0.defaultDatabase = try Salty.appDatabase()
                }
                
                // Create backup after successful database initialization
                let backupManager = DatabaseBackupManager()
                backupManager.createBackupIfNeeded()
            } catch {
                // Log the error but don't crash the app
                logger.error("Failed to initialize database: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .handlesExternalEvents(preferring: ["salty-recipe"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["salty-recipe"])
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
