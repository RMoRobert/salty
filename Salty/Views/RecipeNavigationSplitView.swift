//
//  RecipeNavigationSplitView.swift
//  Salty
//
//  Created by Robert on 10/25/22, re-creaated 7/24/23 and 6/10/25
//

import SwiftUI

struct RecipeNavigationSplitView: View {
    @State var viewModel: RecipeNavigationSplitViewModel
    @AppStorage("webPreviews") private var useWebRecipeDetailView = false
    
//    init(previewData: (recipes: [Recipe], categories: [Category])? = nil) {
//        if let previewData = previewData {
//            self._viewModel = State(initialValue: PreviewRecipeNavigationSplitViewModel(previewData: previewData))
//        } else {
//            self._viewModel = State(initialValue: RecipeNavigationSplitViewModel())
//        }
//    }
    //@Environment(\.openWindow) private var openWindow
    @State private var recipeToEditID: String?

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    //@State private var showEditRecipeView = false
    @State private var showingEditSheet = false
    @State private var showingEditLibCategoriesSheet = false
    @State private var showingOpenDBSheet = false
    @State private var showingImportFromFileSheet = false
    @State private var showingImportFromWebSheet = false
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
                            .font(.caption)
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
            List(selection: $viewModel.selectedRecipeIDs) {
                ForEach(viewModel.filteredRecipes) { recipe in
                    RecipeRowView(recipe: recipe)
                        .contextMenu {
                            Button("Edit") {
                                recipeToEditID = recipe.id
                                showingEditSheet = true
                            }
                            Button(role: .destructive, action: {
                                viewModel.deleteRecipe(id: recipe.id)
                            }) {
                                Text("Delete")
                            }
                            .keyboardShortcut(.delete, modifiers: [.command])
                        }
                }
            }
            .navigationTitle(viewModel.navigationTitle)
            .toolbar {
                Button(role: .destructive, action: {
                    showingDeleteConfirmation = true
                }) {
                    Label("Delete Recipe", systemImage: "minus")
                }
                .disabled(viewModel.selectedRecipeIDs.isEmpty)
                .alert("Delete Recipe\(viewModel.selectedRecipeIDs.count == 1 ? "" : "s")?", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        viewModel.deleteSelectedRecipes()
                    }
                } message: {
                    Text("Are you sure you want to delete \(viewModel.selectedRecipeIDs.count) recipe\(viewModel.selectedRecipeIDs.count == 1 ? "" : "s")? This action cannot be undone.")
                }
                
                Button(action: {
                    viewModel.addNewRecipe()
                }) {
                    Label("New Recipe", systemImage: "plus")
                }
                
                Button(action: {
                    if let firstSelectedID = viewModel.selectedRecipeIDs.first {
                        recipeToEditID = firstSelectedID
                        showingEditSheet = true
                    }
                }) {
                    Label("Edit Recipe", systemImage: "pencil")
                }
                .disabled(viewModel.selectedRecipeIDs.isEmpty)
                .keyboardShortcut("e", modifiers: [.command])
                
                Menu(content: {
                    Button("Import Recipe from Web…") {
                        showingImportFromWebSheet.toggle()
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
        .sheet(isPresented: $showingEditSheet) {
            if let recipe = viewModel.recipeToEdit(recipeId: recipeToEditID) {
                NavigationStack {
                #if os(macOS)
                    RecipeDetailEditDesktopView(recipe: recipe)
                    .frame(minWidth: 600, minHeight: 500)
                #else
                    RecipeDetailEditMobileView(recipe: recipe)
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
        .onChange(of: showingEditSheet) { _, isPresented in
            if !isPresented {
                recipeToEditID = nil
            }
        }
        .sheet(isPresented: $showingOpenDBSheet) {
            OpenDBView()
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
        }
        .sheet(isPresented: $showingImportFromWebSheet) {
            ImportRecipeFromWebView()
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
