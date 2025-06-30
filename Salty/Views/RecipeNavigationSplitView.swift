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
    
    private var recipeToEdit: Recipe? {
        guard let recipeId = recipeToEditID else { return nil }
        return recipes.first(where: { $0.id == recipeId })
    }
    
    private var filteredRecipes: [Recipe] {
        var recipesToFilter: [Recipe]
        
        if selectedSidebarItemId == "0" {
            recipesToFilter = recipes
        } else if let categoryId = selectedSidebarItemId,
                  let category = categories.first(where: { $0.id == categoryId }) {
            // Filter recipes for the selected category
            do {
                let recipeIds = try database.read { db in
                    try RecipeCategory
                        .filter(Column("categoryId") == category.id)
                        .fetchAll(db)
                        .map { $0.recipeId }
                }
                
                recipesToFilter = recipes.filter { recipe in
                    recipeIds.contains(recipe.id)
                }
            } catch {
                recipesToFilter = []
            }
        } else {
            recipesToFilter = []
        }
        
        // Apply search filter if search string is not empty
        if !searchString.isEmpty {
            let normalizedSearch = searchString
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            recipesToFilter = recipesToFilter.filter { recipe in
                let normalizedName = recipe.name
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                
                return normalizedName.contains(normalizedSearch)
            }
        }
        
        return recipesToFilter
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedSidebarItemId) {
                // Library:
                Section {
                    Label("All Recipes", systemImage: "book")
                        .tag("0") // figure out better way to ta all...
                } header: {
                    Text("Library")
                }
                
                // Categories:
                Section {
                    ForEach(categories) { category in
                        Label(category.name, systemImage: "doc.plaintext")
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
            List(selection: $selectedRecipeIDs) {
                ForEach(filteredRecipes) { recipe in
                    RecipeRowView(recipe: recipe)
                        .contextMenu {
                            Button("Edit") {
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
            .navigationTitle(navigationTitle)
            .onDeleteCommand {
                deleteSelectedRecipes()
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
        .searchable(text: $searchString)
        .navigationTitle("Recipes")
        .toolbar {
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
    
    private var navigationTitle: String {
        if selectedSidebarItemId == "0" {
            return "Recipes"
        } else if let categoryId = selectedSidebarItemId,
                  let category = categories.first(where: { $0.id == categoryId }) {
            return category.name
        } else {
            return "Recipes"
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

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try Salty.appDatabase()
    }
    RecipeNavigationSplitView()
}
