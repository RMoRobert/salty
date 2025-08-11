//
//  SaltyApp.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SharingGRDB
import SwiftUI

@main
struct SaltyApp: App {
    @Dependency(\.context) var context
    
    init() {
        if context == .live {
            do {
                try prepareDependencies {
                    $0.defaultDatabase = try Salty.appDatabase()
                }
                
                // Create backup after successful database initialization
                let backupManager = DatabaseBackupManager()
                backupManager.createBackupIfNeeded()
            } catch {
                // Log the error but don't crash the app
                print("Failed to initialize database: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
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
        // "Open Database" window
        WindowGroup(id: "open-database-window") {
            OpenDBView()
                #if os(macOS)
                .frame(minWidth: 300, minHeight: 400)
                #endif
                .navigationTitle("Open Database")
        }

        // "Import from File" window
        WindowGroup(id: "import-from-file-window") {
            ImportRecipesFromFileView()
                .frame(idealWidth: 300)
                .navigationTitle("Import Recipes from File")
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
        Settings {
            SettingsView()
        }
        #endif
    }
}
