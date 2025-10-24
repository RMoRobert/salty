//
//  SaltyApp.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SQLiteData
import SwiftUI

// Global storage for import URL to avoid state reset issues
class ImportURLManager: ObservableObject {
    @Published var pendingImportURL: URL? {
        didSet {
            print("ImportURLManager pendingImportURL changed to: \(String(describing: pendingImportURL))")
        }
    }
    @Published var showingImportSheet = false
}

@main
struct SaltyApp: App {
    @Dependency(\.context) var context
    @Environment(\.openWindow) private var openWindow
    @StateObject private var importURLManager = ImportURLManager()
    
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
                .handlesExternalEvents(preferring: ["salty-recipe"], allowing: ["*"])
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .sheet(isPresented: $importURLManager.showingImportSheet) {
                    ImportRecipesFromFileView(preSelectedFileURL: importURLManager.pendingImportURL)
                        #if os(macOS)
                        .frame(minWidth: 500, minHeight: 400)
                        #endif
                }
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
        Settings {
            SettingsView()
        }
        #endif
    }
    
    private func handleIncomingURL(_ url: URL) {
        // Check if this is a .saltyRecipe file
        if url.pathExtension.lowercased() == "saltyrecipe" {
            print("Received .saltyRecipe file: \(url)")
            importURLManager.pendingImportURL = url
            print("Set importURLManager.pendingImportURL to: \(url)")
            print("Showing import sheet...")
            importURLManager.showingImportSheet = true
        } else {
            print("Received unsupported file type: \(url)")
        }
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
