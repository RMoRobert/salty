//
//  RecipeNavigationSplitView.swift
//  Salty
//
//  Created by Robert on 10/25/22, substantial re-creations on 7/24/23 and 6/10/25
//

import SwiftUI
import UniformTypeIdentifiers

struct RecipeNavigationSplitView: View {
    @State var viewModel: RecipeNavigationSplitViewModel
    @AppStorage("webPreviews") private var useWebRecipeDetailView = false
    @Environment(\.openWindow) private var openWindow

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isEditMode = false
    

    
    //@State private var showEditRecipeView = false
    @State private var showingEditLibCategoriesSheet = false
    @State private var showingEditLibTagsSheet = false
    @State private var showingEditLibCoursesSheet = false
    @State private var showingOpenDBSheet = false
    @State private var showingImportFromFileSheet = false
    @State private var showingCreateFromImageSheet = false
    @State private var showingCreateFromWebSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSettingsSheet = false
    
    private var isAnySheetShown: Bool {
        showingEditLibCategoriesSheet ||
        showingEditLibTagsSheet ||
        showingEditLibCoursesSheet ||
        showingOpenDBSheet ||
        showingImportFromFileSheet ||
        showingCreateFromImageSheet ||
        showingCreateFromWebSheet ||
        showingSettingsSheet
    }
    
    private func notifySheetStateChanged() {
        NotificationCenter.default.post(
            name: .sheetStateChanged,
            object: nil,
            userInfo: ["isShown": isAnySheetShown]
        )
    }
    
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
                        Label(category.name, systemImage: "rectangle.stack")
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
            #if os(macOS)
            .onAppear() {
                // On macOS, set default selection to "All Recipes" if no selection exists
                if viewModel.selectedSidebarItemId == nil {
                    viewModel.selectedSidebarItemId = viewModel.allRecipesID
                }
            }
            #endif

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
                                Button("Export…") {
                                    viewModel.exportRecipe(recipe.id)
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
                    if isEditMode {
                        Button(action: {
                            viewModel.exportSelectedRecipes()
                        }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.selectedRecipeIDs.isEmpty)
                        
                        Button(role: .destructive, action: {
                            showingDeleteConfirmation = true
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(viewModel.selectedRecipeIDs.isEmpty)
                    }
                    
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
                            Label(isEditMode ? "Done" : "Edit", systemImage: isEditMode ? "checkmark" : "pencil")
                        }
                        Divider()
                        Button("Category Editor") {
                            showingEditLibCategoriesSheet = true
                        }
                        Button("Tag Editor") {
                            showingEditLibTagsSheet = true
                        }
                        Button("Course Editor") {
                            showingEditLibCoursesSheet = true
                        }
                        Divider()
                        Button("Create Recipe from Image…") {
                            showingCreateFromImageSheet.toggle()
                        }
                        Button("Import Recipes from File…") {
                            showingImportFromFileSheet.toggle()
                        }
                        Button("Create Recipe from Web…") {
                            showingCreateFromWebSheet.toggle()
                        }
                        Button("Open Database…") {
                            showingOpenDBSheet.toggle()
                        }
                        #if !os(macOS)
                        Divider()
                        Button("Settings…") {
                            showingSettingsSheet = true
                        }
                        #endif
                    }, label: {
                        Label("More", systemImage: "ellipsis.circle")
                    })
                }
                #else
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: {
                        viewModel.exportSelectedRecipes()
                    }) {
                        Label("Export Recipe", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.selectedRecipeIDs.isEmpty)
                    
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
                            #if os(iOS)
                            showingCreateFromWebSheet.toggle()
                            #else
                            openWindow(id: "create-recipe-from-web-window")
                            #endif
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
            .fileExporter(
                isPresented: $viewModel.showingExportSheet,
                document: ExportDocument(data: viewModel.exportData ?? Data(), suggestedName: viewModel.exportFileName),
                contentType: .saltyRecipe,
                defaultFilename: viewModel.exportFileName
            ) { result in
                switch result {
                case .success(_):
                    // Export successful
                    break
                case .failure(let error):
                    viewModel.exportErrorMessage = "Export failed: \(error.localizedDescription)"
                    viewModel.showingExportErrorAlert = true
                }
            }
            .alert("Export Failed", isPresented: $viewModel.showingExportErrorAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.exportErrorMessage)
            }
            #if os(macOS)
            .onDeleteCommand {
                if !viewModel.selectedRecipeIDs.isEmpty {
                    showingDeleteConfirmation = true
                }
            }
            #endif
            .searchable(text: $viewModel.searchString)
        } detail: {
            if let recipeId = viewModel.selectedRecipeIDs.first,
               let recipe = viewModel.recipes.first(where: { $0.id == recipeId }) {
                if useWebRecipeDetailView == true {
                    RecipeDetailWebView(recipe: recipe)
                        .id(recipeId) // seems to be needed to force full reload when recipe changes?
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button(action: {
                                    viewModel.recipeToEditID = recipeId
                                    viewModel.showingEditSheet = true
                                }) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .keyboardShortcut("e", modifiers: .command)
                            }
                        }
                }
                else {
                    RecipeDetailView(recipe: recipe)
                        .id(recipeId) // seems to be needed to force full reload when recipe changes?
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button(action: {
                                    viewModel.recipeToEditID = recipeId
                                    viewModel.showingEditSheet = true
                                }) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .keyboardShortcut("e", modifiers: .command)
                            }
                        }
                }
            } else {
                Text("No recipe selected")
                    .foregroundStyle(.tertiary)
                    .font(.title)
            }
        }
        .navigationTitle("Recipes")
        .sheet(isPresented: $viewModel.showingEditSheet) {
            if let recipe = viewModel.recipeToEdit(recipeId: viewModel.recipeToEditID) {
                let isNewRecipe = viewModel.isDraftRecipe(viewModel.recipeToEditID)
                NavigationStack {
                    #if os(macOS)
                    RecipeDetailEditDesktopView(recipe: recipe, isNewRecipe: isNewRecipe, onNewRecipeSaved: viewModel.handleNewRecipeSaved)
                        .frame(minWidth: 625, minHeight: 650)
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
        .fullScreenCover(isPresented: $showingCreateFromWebSheet) {
            CreateRecipeFromWebView()
//            #if os(macOS)
//                .frame(minWidth: 800, minHeight: 700)
//            #endif
        }
        .sheet(isPresented: $showingEditLibCategoriesSheet) {
            #if os(iOS)
            NavigationStack {
                LibraryCategoriesEditView()
            }
            #else
            LibraryCategoriesEditView()
                .frame(minWidth: 500, minHeight: 400)
            #endif
        }
        .sheet(isPresented: $showingEditLibTagsSheet) {
            #if os(iOS)
            NavigationStack {
                LibraryTagsEditView()
            }
            #else
            LibraryTagsEditView()
                .frame(minWidth: 500, minHeight: 400)
            #endif
        }
        .sheet(isPresented: $showingEditLibCoursesSheet) {
            #if os(iOS)
            NavigationStack {
                LibraryCoursesEditView()
            }
            #else
            LibraryCoursesEditView()
                .frame(minWidth: 500, minHeight: 400)
            #endif
        }
        .sheet(isPresented: $showingSettingsSheet) {
            NavigationStack {
                SettingsView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSelectedRecipes)) { _ in
            viewModel.exportSelectedRecipes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showImportFromFileSheet)) { _ in
            showingImportFromFileSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOpenDatabaseSheet)) { _ in
            showingOpenDBSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCreateFromWebSheet)) { _ in
            showingCreateFromWebSheet = true
        }
        .onChange(of: isAnySheetShown) { _, _ in
            notifySheetStateChanged()
        }
    }
}

#Preview {
    RecipeNavigationSplitView(
        viewModel: RecipeNavigationSplitViewModel()
    )
}

// MARK: - Export Document

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.saltyRecipe] }
    
    var data: Data
    var suggestedName: String
    
    init(data: Data, suggestedName: String = "recipe") {
        self.data = data
        self.suggestedName = suggestedName
    }
    
    init(configuration: ReadConfiguration) throws {
        data = Data()
        suggestedName = "recipe"
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}


