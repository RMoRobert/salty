//
//  RecipeNavigationSplitView.swift
//  Salty
//
//  Created by Robert on 10/25/22, re-creaated 7/24/23 and 6/10/25
//

import SwiftUI
import SharingGRDB

struct RecipeNavigationSplitView: View {
    @Dependency(\.defaultDatabase) private var database
    //@Environment(\.openWindow) private var openWindow
    @State private var recipeToEditID: String?
    
    @FetchAll
    var recipes: [Recipe]
    
    @FetchAll
    var categories: [Category]
    
//    @FetchAll
//    var shoppingLists: [ShoppingList]
    
    @State private var searchString = ""
    @State private var selectedSidebarItemId: String?
    @State private var selectedRecipeIDs = Set<String>()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    //@State private var showEditRecipeView = false
    @State private var showingEditSheet = false
    @State private var showingEditLibCategoriesSheet = false
    @State private var showingOpenDBSheet = false
    @State private var showingImportRecipesSheet = false
    
    // Removed computed property that was causing performance issues
    
//    var filteredRecipes: [Recipe] {
    
    private var recipeToEdit: Recipe? {
        guard let recipeId = recipeToEditID else { return nil }
        return recipes.first(where: { $0.id == recipeId })
    }
    
//    var filteredRecipes: [Recipe] {
//        if searchString.isEmpty {
//            return viewModel.recipes
//        } else {
//            return viewModel.recipes.filter { recipe in
//                recipe.name.localizedCaseInsensitiveContains(searchString)
//            }
//        }
//    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedSidebarItemId) {
                // Library:
                Section {
                    Text("All Recipes")
                        .tag("0") // figure out better way to ta all...
                } header: {
                    Text("Library")
                }
                
                // Categories:
                Section {
                    ForEach(categories) { category in
                        Text(category.name)
                            .tag(category.id)
                    }
                } header: {
                    Text("Categories")
                }
//                // Smart Lists:
//                Section {
//                    Text("Coming Soon")
//                } header: {
//                    Text("Smart Lists")
//                }
            }
            .listStyle(.sidebar)
        } content: {
            if selectedSidebarItemId == "0" {
                // Show all recipes
                List(selection: $selectedRecipeIDs) {
                    ForEach(recipes) { recipe in
                        RecipeRowView(recipe: recipe)
                            .contextMenu {
                                Button("Edit") {
                                    //print("Edit button pressed for recipe: \(recipe.name)")
                                    recipeToEditID = recipe.id
                                    showingEditSheet = true
                                }
                                Button(role: .destructive, action: {
                                    // TODO: Re-add delete recipe action!
//                                    if let id = recipe.id {
//                                        viewModel.deleteRecipe(id: id)
//                                    }
                                }) {
                                    Text("Delete")
                                }
                                .keyboardShortcut(.delete, modifiers: [.command])
                            }
                    }
                }
                .navigationTitle("Recipes")
            } else if let categoryId = selectedSidebarItemId,
                      let category = categories.first(where: { $0.id == categoryId }) {
                // Show category recipes
                CategoryRecipesView(category: category)
            } else {
                Text("No category/list selected")
                    .foregroundStyle(.tertiary)
            }
        } detail: {
            if let recipeId = selectedRecipeIDs.first,
               let recipe = recipes.first(where: { $0.id == recipeId }) {
                //RecipeDetailWebView(recipe: recipe)
                RecipeDetailView(recipe: recipe)
            } else {
                Text("No recipe selected")
                    .foregroundStyle(.tertiary)
                    .font(.title)
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            if selectedSidebarItemId == "0" {
                Menu(content: {
                    Button("Open Database…") {
                        showingOpenDBSheet.toggle()
                    }
                    Button("Import Recipes…") {
                        showingImportRecipesSheet.toggle()
                    }
                }, label: {
                    Label("More", systemImage: "ellipsis.circle")
                })
                Button(role: .destructive, action: deleteSelectedRecipes) {
                    Label("Delete Recipe", systemImage: "minus")
                }
                .disabled(selectedRecipeIDs.isEmpty)
                Button(action: {
                    try? database.write { db in
                        let newRecipe = Recipe(
                            id: UUID().uuidString,
                            name: "New Recipe",
                            createdDate: Date(),
                            lastModifiedDate: Date(),
                            lastPrepared: Date(timeIntervalSinceNow: 0-60*24*45),                  isFavorite: false,
                            wantToMake: false
                        )
                        try? newRecipe.insert(db)
                    }
                    
                }) {
                    Label("New Recipe", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let recipe = recipeToEdit {
                RecipeDetailEditView(recipe: recipe)
                    .frame(minWidth: 600, minHeight: 500)
            }
        }
        .onChange(of: showingEditSheet) { _, isPresented in
            if !isPresented {
                recipeToEditID = nil
            }
        }
    }
    
    private func deleteSelectedRecipes() {
        try? database.write { db in
            for id in selectedRecipeIDs {
                try Recipe.deleteOne(db, key: id)
            }
        }
        selectedRecipeIDs.removeAll()
    }
}

struct CategoryRecipesView: View {
    var category: Category?
    var body: some View {
        Text("To do!")
    }
}

//  Old implementation
//struct CategoryRecipesViewOLD: View {
//    let category: Category
//    @StateObject private var viewModel = RecipeListViewModel()
//    @State private var selectedRecipeIDs = Set<String>()
//    
//    var body: some View {
//        List(selection: $selectedRecipeIDs) {
//            ForEach(viewModel.recipes) { recipe in
//                RecipeRowView(recipe: recipe)
//                    .contextMenu {
//                        Button(role: .destructive, action: {
//                            if let id = recipe.id {
//                                viewModel.deleteRecipe(id: id)
//                            }
//                        }) {
//                            Text("Delete")
//                        }
//                        .keyboardShortcut(.delete, modifiers: [.command])
//                    }
//            }
//        }
//        .navigationTitle("Recipes")
//        .toolbar {
//            Button(role: .destructive, action: deleteSelectedRecipes) {
//                Label("Delete Recipe", systemImage: "minus")
//            }
//            Button(action: { viewModel.createRecipe(name: "New Recipe") }) {
//                Label("New Recipe", systemImage: "plus")
//            }
//        }
//    }
//    
//    private func deleteSelectedRecipes() {
//        for id in selectedRecipeIDs {
//            viewModel.deleteRecipe(id: id)
//        }
//        //selectedRecipeIDs.removeAll()
//    }
//}


#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try Salty.appDatabase()
    }
    RecipeNavigationSplitView()
}
