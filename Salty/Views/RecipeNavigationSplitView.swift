//
//  RecipeNavigationSplitView.swift
//  Salty
//
//  Created by Robert on 10/25/22, re-creaated 7/24/23
//

import SwiftUI
import RealmSwift

struct RecipeNavigationSplitViewNEW: View {
    @ObservedRealmObject var recipeLibrary: RecipeLibrary
    @Environment(\.openWindow) private var openWindow
    @State private var searchString = ""
    @State private var selectedSidebarItemId: RealmSwift.ObjectId?
    @State private var selectedRecipeIDs = Set<RealmSwift.ObjectId>()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    @State private var showEditRecipeView = false
    @State private var showingEditLibCategoriesSheet = false
    @State private var showingOpenDBSheet = false
    @State private var showingImportRecipesSheet = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedSidebarItemId) {
                // Library:
                Section {
                    Label("All Recipes", systemImage: "book")
                        .tag(recipeLibrary._id)
                }
                header: {
                    Text("Library")
                }
                // Categories:
                Section {
                    ForEach(recipeLibrary.categories.sorted(byKeyPath: "name")) { category in
                        Label(category.name, systemImage: "doc.plaintext")
                            .tag(category._id)
                    }
                }
                header: {
                    Text("Categories")
                }
                // Smart Lists:
                Section {
                    Label("Coming Soon", systemImage: "doc.text.magnifyingglass")
                    }
                header: {
                    Text("Smart Lists")
                }
                // Shopping Lists
                Section {
                    ForEach(recipeLibrary.shoppingLists.sorted(byKeyPath: "name")) { shoppingList in
                        Label(shoppingList.name, systemImage: "list.bullet.rectangle")
                            .tag(shoppingList._id)
                    }
                }
                header: {
                    Text("Shopping Lists")
                }
            }
            .listStyle(.sidebar)
        }
    content: {
        Text("No category/list selected")
            .foregroundStyle(.tertiary)
    }
    detail: {
        Text("No recipe selected")
            .foregroundStyle(.tertiary)
    }
    .navigationTitle("Recipes")
    }
    
    func deleteSelectedRecipes() -> () {
        // TODO: there has to be a better way?
        let ids = selectedRecipeIDs.map { $0 }
        ids.forEach { theId in
            if let theIdx = recipeLibrary.recipes.firstIndex(where: {
                $0._id == theId
            }) {
                $recipeLibrary.recipes.remove(at: theIdx)
            }
        }
    }
    
    func addNewShoppingist() -> () {
        let sl = ShoppingList()
        sl.name = "New Shopping List"
        $recipeLibrary.shoppingLists.append(sl)
    }
}

struct RecipeNavigationSplitViewNEW_Preview: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let lib = realm.objects(RecipeLibrary.self)        
        RecipeNavigationSplitViewNEW(recipeLibrary: lib.first!)
    }
}
