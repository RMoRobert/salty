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
    //let persistenceController = PersistenceController.shared
    init() {
        if context == .live {
            try! prepareDependencies {
                $0.defaultDatabase = try Salty.appDatabase()
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
                .frame(idealWidth: 300)
                .navigationTitle("Category Editor")
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
        WindowGroup(id: "import-from-web-window") {
            ImportRecipeFromWebView()
                .frame(idealWidth: 800)
                .navigationTitle("Import Recipe from Web")
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
