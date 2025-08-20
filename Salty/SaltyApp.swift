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
    @Environment(\.openWindow) private var openWindow
    @State private var pendingImportURL: URL?
    
    init() {
        if context == .live {
            do {
                // Proactively refresh bookmarks to prevent permission issues
                FileManager.refreshBookmarksIfNeeded()
                
                // Validate database access before attempting to open it
                if !FileManager.validateDatabaseAccess() {
                    print("Warning: Database access validation failed. Attempting to refresh bookmarks...")
                    if FileManager.refreshCustomDatabaseBookmark() {
                        print("Successfully refreshed database bookmarks")
                    } else {
                        print("Failed to refresh database bookmarks - may need user intervention")
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
                print("Failed to initialize database: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .onOpenURL { url in
                    handleIncomingURL(url)
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
            if let url = pendingImportURL {
                ImportRecipesFromFileView(preSelectedFileURL: url)
                    .frame(minWidth: 500, minHeight: 400)
                    .navigationTitle("Import Recipe from File")
            }
        }
        .defaultSize(width: 550, height: 450)
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
    
    private func handleIncomingURL(_ url: URL) {
        // Check if this is a .saltyRecipe file
        if url.pathExtension.lowercased() == "saltyrecipe" {
            print("Received .saltyRecipe file: \(url)")
            pendingImportURL = url
            openWindow(id: "import-from-file-window")
        } else {
            print("Received unsupported file type: \(url)")
        }
    }
}
