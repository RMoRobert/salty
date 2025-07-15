//
//  RecipeNavigationSplitView.swift
//  Salty
//
//  Created by Robert on 10/25/22, substantial re-creations on 7/24/23 and 6/10/25
//

import SwiftUI

struct RecipeNavigationSplitView: View {
    @State var viewModel: RecipeNavigationSplitViewModel
    @AppStorage("webPreviews") private var useWebRecipeDetailView = false
    @AppStorage("mobileEditViews") private var useMobileEditViews = false
    @Environment(\.openWindow) private var openWindow

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isEditMode = false
    
    //@State private var showEditRecipeView = false
    @State private var showingEditLibCategoriesSheet = false
    @State private var showingOpenDBSheet = false
    @State private var showingImportFromFileSheet = false
    @State private var showingCreateFromImageSheet = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $viewModel.selectedSidebarItemId) {
                // Library:
                Section {
                    Label("All Recipes", systemImage: "book")
                        .tag(viewModel.allRecipesID) // figure out better way to tag all...
                } header: {
                    Text("Library")
                }
                
                // Categories:
                Section {
                    ForEach(viewModel.categories) { category in
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
            .onAppear() {
                viewModel.selectedSidebarItemId = viewModel.allRecipesID
            }
        } content: {
            ScrollViewReader { proxy in
                List(selection: $viewModel.selectedRecipeIDs) {
                    ForEach(viewModel.filteredRecipes) { recipe in
                        RecipeRowView(recipe: recipe)
                            .id(recipe.id)
                            .contextMenu {
                                Button("Edit") {
                                    viewModel.recipeToEditID = recipe.id
                                    viewModel.showingEditSheet = true
                                }
                                Button(role: .destructive, action: {
                                    withAnimation {
                                        viewModel.deleteRecipe(id: recipe.id)
                                    }
                                }) {
                                    Text("Delete")
                                }
                                .keyboardShortcut(.delete, modifiers: [.command])
                            }
                    }
                    #if !os(macOS)
                    .onDelete { indexSet in
                        withAnimation {
                            let recipesToDelete = indexSet.compactMap { index in
                                viewModel.filteredRecipes.indices.contains(index) ? viewModel.filteredRecipes[index] : nil
                            }
                            for recipe in recipesToDelete {
                                viewModel.deleteRecipe(id: recipe.id)
                            }
                        }
                    }
                    #endif
                }
                #if !os(macOS)
                .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
                .onChange(of: isEditMode) { _, newValue in
                    if !newValue {
                        // Clear selection when exiting edit mode
                        viewModel.selectedRecipeIDs.removeAll()
                    }
                }
                #endif
                .onChange(of: viewModel.shouldScrollToNewRecipe) { _, shouldScroll in
                    if shouldScroll, let newId = viewModel.selectedRecipeIDs.first {
                        // Wait a bit for the recipe to appear in the list before scrolling
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if viewModel.filteredRecipes.contains(where: { $0.id == newId }) {
                                withAnimation {
                                    proxy.scrollTo(newId)
                                }
                            }
                        }
                        // Reset the flag after attempting to scroll
                        viewModel.shouldScrollToNewRecipe = false
                    }
                }
            }
            .navigationTitle(viewModel.navigationTitle)
            .toolbar {
                #if !os(macOS)
                ToolbarItemGroup(placement: .navigationBarTrailing) {
//                    if isEditMode && !viewModel.selectedRecipeIDs.isEmpty {
//                        Button(role: .destructive, action: {
//                            showingDeleteConfirmation = true
//                        }) {
//                            Label("Delete", systemImage: "trash")
//                        }
//                    }
                    
                    Button(action: {
                        viewModel.addNewRecipe()
                    }) {
                        Label("New Recipe", systemImage: "plus")
                    }
                    .disabled(isEditMode)
                    
                    Menu(content: {
                        Toggle(isOn: $viewModel.isFavoritesFilterActive) {
                            Label("Filter (Favorites Only)", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        Divider()
                        Button(action: {
                            isEditMode.toggle()
                        }) {
                            Label(isEditMode ? "Done" : "Edit", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button("Create Recipe from Image…") {
                            showingCreateFromImageSheet.toggle()
                        }
                        Button("Import Recipes from File…") {
                            showingImportFromFileSheet.toggle()
                        }
                        Button("Open Database…") {
                            showingOpenDBSheet.toggle()
                        }
                    }, label: {
                        Label("More", systemImage: "ellipsis.circle")
                    })
                }
                #else
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete Recipe", systemImage: "trash")
                    }
                    .disabled(viewModel.selectedRecipeIDs.isEmpty)
                    
                    Button(action: {
                        viewModel.addNewRecipe()
                    }) {
                        Label("New Recipe", systemImage: "plus")
                    }
                    Toggle(isOn: $viewModel.isFavoritesFilterActive) {
                        Label("Filter (Favorites Only)", systemImage: "line.3.horizontal.decrease.circle")
                    }
                   // .buttonStyle(.button)
                    Menu(content: {
                        Button("Create Recipe from Web…") {
                            openWindow(id: "create-recipe-from-web-window")
                        }
                        Button("Create Recipe from Image…") {
                            showingCreateFromImageSheet.toggle()
                        }
                        Button("Import Recipes from File…") {
                            showingImportFromFileSheet.toggle()
                        }
                        Divider()
                        Button("Open Database…") {
                            showingOpenDBSheet.toggle()
                        }
                    }, label: {
                        Label("More", systemImage: "ellipsis.circle")
                    })
                }
                #endif
            }
            .alert("Delete Recipe\(viewModel.selectedRecipeIDs.count == 1 ? "" : "s")?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    withAnimation {
                        viewModel.deleteSelectedRecipes()
                    }
                    #if !os(macOS)
                    // Delay exiting edit mode to let deletion animation complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isEditMode = false
                    }
                    #endif
                }
            } message: {
                Text("Are you sure you want to delete \(viewModel.selectedRecipeIDs.count) recipe\(viewModel.selectedRecipeIDs.count == 1 ? "" : "s")? This action cannot be undone.")
            }
            #if os(macOS)
            .onDeleteCommand {
                if !viewModel.selectedRecipeIDs.isEmpty {
                    showingDeleteConfirmation = true
                }
            }
            #endif
        } detail: {
            if let recipeId = viewModel.selectedRecipeIDs.first,
               let recipe = viewModel.recipes.first(where: { $0.id == recipeId }) {
                #if os(macOS)
                if useWebRecipeDetailView == true {
                    RecipeDetailWebView(recipe: recipe)
                        .id(recipeId) // seems to be needed to force full reload when recipe changes?
                }
                else {
                    RecipeDetailView(recipe: recipe)
                        .id(recipeId) // seems to be needed to force full reload when recipe changes?
                }
                #else
                    RecipeDetailView(recipe: recipe)
                        .id(recipeId) // seems to be needed to force full reload when recipe changes?
                #endif
            } else {
                Text("No recipe selected")
                    .foregroundStyle(.tertiary)
                    .font(.title)
            }
        }
        .searchable(text: $viewModel.searchString)
        .navigationTitle("Recipes")
        .sheet(isPresented: $viewModel.showingEditSheet) {
            if let recipe = viewModel.recipeToEdit(recipeId: viewModel.recipeToEditID) {
                let isNewRecipe = viewModel.isDraftRecipe(viewModel.recipeToEditID)
                NavigationStack {
                    #if os(macOS)
                    if useMobileEditViews {
                        RecipeDetailEditMobileView(recipe: recipe, isNewRecipe: isNewRecipe, onNewRecipeSaved: viewModel.handleNewRecipeSaved)
                            .frame(minWidth: 600, minHeight: 500)
                    } else {
                        RecipeDetailEditDesktopView(recipe: recipe, isNewRecipe: isNewRecipe, onNewRecipeSaved: viewModel.handleNewRecipeSaved)
                            .frame(minWidth: 600, minHeight: 500)
                    }
                    #else
                    RecipeDetailEditMobileView(recipe: recipe, isNewRecipe: isNewRecipe, onNewRecipeSaved: viewModel.handleNewRecipeSaved)
                    #endif
                }
            }
        }
        .sheet(isPresented: $showingImportFromFileSheet) {
            ImportRecipesFromFileView()
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
        .onChange(of: viewModel.showingEditSheet) { _, isPresented in
            if !isPresented {
                viewModel.clearDraftRecipe()
                viewModel.recipeToEditID = nil
            }
        }
        .sheet(isPresented: $showingOpenDBSheet) {
            OpenDBView()
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
        }
        .sheet(isPresented: $showingCreateFromImageSheet) {
            CreateRecipeFromImageView()
            #if os(macOS)
                .frame(minWidth: 800, minHeight: 700)
            #endif
        }

    }
    

    

}

#Preview {
    RecipeNavigationSplitView(
        viewModel: RecipeNavigationSplitViewModel()
    )
}
