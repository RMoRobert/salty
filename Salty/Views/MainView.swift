//
//  ContentView.swift
//  Salty
//
//  Created by Robert on 4/17/23.
//

import SwiftUI
import RealmSwift

@main
struct ContentView: SwiftUI.App {
    let realmConfig = Realm.Configuration(
        fileURL: FileManager.defaultSaltyLibraryPath
    )
    var body: some Scene {
        // Main view
        WindowGroup {
            MainVew()
                .environment(\.realmConfiguration, realmConfig)
        }
        .commands {
            Menus()
        }
        // "Edit Categories" window
        WindowGroup(id: "edit-categories-window") {
            LibraryCategoriesEditView()
                .environment(\.realmConfiguration, realmConfig)
                .frame(idealWidth: 300)
        }
        // "Import" window
        WindowGroup(id: "import-page") {
            ImportView()
                .environment(\.realmConfiguration, realmConfig)
                .frame(idealWidth: 400)
        }
    }
}

struct MainVew: View {
    @State var searchFilter: String = ""
    // Implicitly use the default realm's objects(RecipeLibrary.self)
    @ObservedResults(RecipeLibrary.self) var recipeLibraries

    var body: some View {
        
        if let recipeLibrary = recipeLibraries.first {
            // Pass the RecipeLibrary objects to a view further down the hierarchy:
            RecipeNavigationSplitView(recipeLibrary: recipeLibrary)
        } else {
            // For this small app, we only want one recipeLibrary in the realm.
            // You can expand this app to support multiple recipeLibraries.
            // For now, if there is no recipeLibrary, add one here.
            ProgressView().onAppear {
                $recipeLibraries.append(RecipeLibrary())
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainVew()
    }
}
