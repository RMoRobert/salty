// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

//
//  RecipeNavigationSplitView.swift
//  Salty
//
//  Created by Robert on 10/25/22, substantial re-creations on 7/24/23 and 6/10/25
//

import SwiftUI
import UniformTypeIdentifiers
#if !os(macOS)
import UIKit
#endif

// MARK: - Conditional List Row Background Modifier

private struct ConditionalListRowBackground<Background: View>: ViewModifier {
    let isTargeted: Bool
    let background: Background
    
    func body(content: Content) -> some View {
        if isTargeted {
            content
                .listRowBackground(background)
        } else {
            content
        }
    }
}

// MARK: - Drop Target Views

private struct CategoryDropTargetView: View {
    let category: Category
    let viewModel: RecipeNavigationSplitViewModel
    @State private var isTargeted = false
    
    private var dropTargetBackground: some View {
        Color.accentColor
            .clipShape(.rect(cornerRadius: 5))
            .opacity(0.15)
            .padding(.horizontal, 10)
    }
    
    var body: some View {
        Label(category.name, systemImage: "rectangle.stack")
            .tag("cat_\(category.id)")
            .dropDestination(for: String.self) { recipeIds, location in
                for recipeId in recipeIds {
                    Task { await viewModel.addRecipeToCategory(recipeId: recipeId, categoryId: category.id) }
                }
                return !recipeIds.isEmpty
            } isTargeted: { hovering in
                isTargeted = hovering
            }
            .modifier(ConditionalListRowBackground(isTargeted: isTargeted, background: dropTargetBackground))
    }
}

private struct TagDropTargetView: View {
    let tag: Tag
    let viewModel: RecipeNavigationSplitViewModel
    @State private var isTargeted = false
    
    private var dropTargetBackground: some View {
        Color.accentColor
            .clipShape(.rect(cornerRadius: 5))
            .opacity(0.15)
            .padding(.horizontal, 10)
    }
    
    var body: some View {
        Label(tag.name, systemImage: "tag")
            .tag("tag_\(tag.id)")
            .dropDestination(for: String.self) { recipeIds, location in
                for recipeId in recipeIds {
                    Task { await viewModel.addRecipeToTag(recipeId: recipeId, tagId: tag.id) }
                }
                return !recipeIds.isEmpty
            } isTargeted: { hovering in
                isTargeted = hovering
            }
            .modifier(ConditionalListRowBackground(isTargeted: isTargeted, background: dropTargetBackground))
    }
}

struct RecipeNavigationSplitView: View {
    // Received from MainView (which owns it via @State). @Bindable provides the `$viewModel`
    // bindings this view needs without taking a second, competing ownership of the instance.
    @Bindable var viewModel: RecipeNavigationSplitViewModel
    @AppStorage("webPreviews") private var useWebRecipeDetailView = false
    @AppStorage("offeredSampleImport") private var offeredSampleImport = false
    // To force for testing:
    //@State private var offeredSampleImport = false
    @Environment(\.openWindow) private var openWindow
    @State private var searchOptionsTracker = SearchOptionsTracker()
    
    @AppStorage("sidebarShowCategories") private var showCategories = true
    @AppStorage("sidebarShowCourses") private var showCourses = true
    @AppStorage("sidebarShowTags") private var showTags = true
    @AppStorage("sidebarExpandCategories") private var expandCategories = true
    @AppStorage("sidebarExpandCourses") private var expandCourses = true
    @AppStorage("sidebarExpandTags") private var expandTags = true

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isEditMode = false
    
    //@State private var showEditRecipeView = false
    @State private var showingEditLibCategoriesSheet = false
    @State private var showingEditLibTagsSheet = false
    @State private var showingEditLibCoursesSheet = false
    @State private var showingImportFromFileSheet = false
    @State private var showingCreateFromImageSheet = false
    @State private var showingCreateFromWebSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSettingsSheet = false
    @State private var showingFirstLaunchAlert = false
    @State private var recipeIDForInspector: String? = nil
    
    private var isAnySheetShown: Bool {
        showingEditLibCategoriesSheet ||
        showingEditLibTagsSheet ||
        showingEditLibCoursesSheet ||
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
    
    private func postRecipeSelectionChanged() {
        let count = viewModel.selectedRecipeIDs.count
        NotificationCenter.default.post(
            name: .recipeSelectionChanged,
            object: nil,
            userInfo: ["hasSelected": count > 0, "count": count]
        )
    }
    
    #if os(macOS)
    private func openRecipeInNewWindow(recipeId: String) {
        openWindow(id: "recipe-detail-window", value: recipeId)
    }
    
    private func openSelectedRecipesInNewWindows(recipeIds: Set<String>) {
        let orderedIds = viewModel.recipes
            .filter { recipeIds.contains($0.id) }
            .map(\.id)
        for recipeId in orderedIds {
            openRecipeInNewWindow(recipeId: recipeId)
        }
    }
    
    private func openSelectedRecipesInNewWindows() {
        openSelectedRecipesInNewWindows(recipeIds: viewModel.selectedRecipeIDs)
    }
    #endif
    
    private func importSampleRecipes() {
        Task {
            await viewModel.importSampleRecipes()
            await MainActor.run {
                offeredSampleImport = true
            }
        }
    }
    
    private var recipeQueryId: String {
        // Include search options in the query ID so changes trigger refresh
        // Use the tracker's changeId to force update when search options change
        let searchOptionsKey = RecipeListSearchOptions.allCases
            .map { UserDefaults.standard.bool(forKey: $0.userDefaultsKey) ? "1" : "0" }
            .joined(separator: "")
        return "\(viewModel.searchString)||\(viewModel.selectedSidebarItemId ?? "")||\(viewModel.isFavoritesFilterActive)||\(viewModel.recipeListSortOrder.rawValue)||\(viewModel.recipeListSortDirection.rawValue)||\(searchOptionsKey)||\(searchOptionsTracker.changeId.uuidString)"
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
                if showCategories {
                    Section(isExpanded: $expandCategories) {
                        ForEach(viewModel.categories) { category in
                            CategoryDropTargetView(
                                category: category,
                                viewModel: viewModel
                            )
                        }
                    } header: {
                        Text("Categories")
                    }
                }
                
                // Courses:
                if showCourses {
                    Section(isExpanded: $expandCourses) {
                        ForEach(viewModel.courses) { course in
                            Label(course.name, systemImage: "fork.knife")
                                .tag("course_\(course.id)")
                        }
                    } header: {
                        Text("Courses")
                    }
                }
                
                // Tags:
                if showTags {
                    Section(isExpanded: $expandTags) {
                        ForEach(viewModel.tags) { tag in
                            TagDropTargetView(
                                tag: tag,
                                viewModel: viewModel
                            )
                        }
                    } header: {
                        Text("Tags")
                    }
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
                } else if let selectedId = viewModel.selectedSidebarItemId,
                          selectedId != viewModel.allRecipesID,
                          !selectedId.hasPrefix("cat_"),
                          !selectedId.hasPrefix("course_"),
                          !selectedId.hasPrefix("tag_") {
                    // Migrate legacy category ID (without prefix) to new format
                    viewModel.selectedSidebarItemId = "cat_\(selectedId)"
                }
            }
            #endif

        } content: {
            ScrollViewReader { proxy in
                List(selection: $viewModel.selectedRecipeIDs) {
                    ForEach(viewModel.recipes) { recipe in
                        RecipeRowView(recipe: recipe)
                            .popover(isPresented: Binding(
                                get: { recipeIDForInspector == recipe.id },
                                set: { if !$0 { recipeIDForInspector = nil } }
                            )) {
                                RecipeInfoInspectorView(recipe: recipe)
                                    .frame(minWidth: 280)
                            }
                            .id(recipe.id)
                            .tag(recipe.id)
                            .draggable(recipe.id)
                            #if !os(macOS)
                            .contextMenu {
                                contextMenuForRecipe(recipe)
                            }
                            #endif
                    }
                    #if !os(macOS)
                    .onDelete { indexSet in
                        withAnimation {
                            let recipesToDelete = indexSet.compactMap { index in
                                viewModel.recipes.indices.contains(index) ? viewModel.recipes[index] : nil
                            }
                            for recipe in recipesToDelete {
                                Task { await viewModel.deleteRecipe(id: recipe.id) }
                            }
                        }
                    }
                    #endif
                    if (viewModel.recipes.isEmpty) {
                        HStack {
                            Spacer()
                            Text("No recipes")
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                #if os(macOS)
                .contextMenu(forSelectionType: String.self) { selectedIDs in
                    contextMenuForSelection(selectedIDs)
                } primaryAction: { selectedIDs in
                    openSelectedRecipesInNewWindows(recipeIds: selectedIDs)
                }
                #endif
                .task(id: recipeQueryId) {
                    await viewModel.updateRecipesQuery()
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
                        Task {
                            try? await Task.sleep(for: .seconds(0.5))
                            if viewModel.recipes.contains(where: { $0.id == newId }) {
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
                    
                    Menu {
                        Button(action: {
                            viewModel.addNewRecipe()
                        }) {
                            Label("New Recipe", systemImage: "plus")
                        }
                        Divider()
                        Button("Create from Image…") {
                            showingCreateFromImageSheet = true
                        }
                        Button("Import from File…") {
                            showingImportFromFileSheet = true
                        }
                        Button("Create from Web…") {
                            showingCreateFromWebSheet = true
                        }
                    } label: {
                        Label("New Recipe", systemImage: "plus")
                    } primaryAction: {
                        viewModel.addNewRecipe()
                    }
                    .disabled(isEditMode)
                    
                    Menu(content: {
                        Button(action: {
                            isEditMode.toggle()
                        }) {
                            Label(isEditMode ? "Done" : "Edit", systemImage: isEditMode ? "checkmark" : "pencil")
                        }
                        Toggle(isOn: $viewModel.isFavoritesFilterActive) {
                            Label("Filter (Favorites Only)", systemImage: isLiquidGlassAvailable() ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle")
                        }
                        #if !os(macOS)
                        Divider()
                        Menu("Sort By", systemImage: "arrow.up.arrow.down") {
                            Picker("Sort Options", selection: Binding(
                                get: { viewModel.recipeListSortOrder },
                                set: { viewModel.recipeListSortOrder = $0 }
                            )) {
                                ForEach(RecipeListSortOrderSetting.allCases, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            Picker("Sort Direction", selection: Binding(
                                get: { viewModel.recipeListSortDirection },
                                set: { viewModel.recipeListSortDirection = $0 }
                            )) {
                                ForEach(RecipeListSortDirection.allCases, id: \.self) { direction in
                                    Text(direction.displayName).tag(direction)
                                }
                            }
                        }
                        Menu("Search Options") {
                            Section("Search In…") {
                                ForEach(RecipeListSearchOptions.allCases, id: \.self) { option in
                                    Toggle(option.displayName, isOn: binding(for: option))
                                }
                            }
                        }
                        #endif
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

                        #if !os(macOS)
                        Divider()
                        Button("Settings…", systemImage: "gear") {
                            showingSettingsSheet = true
                        }
                        #endif
                    }, label: {
                        Label("More", systemImage: isLiquidGlassAvailable() ? "ellipsis" : "ellipsis.circle")
                    })
                }
                #else
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            viewModel.exportSelectedRecipes()
                        }) {
                            Label("Export as Recipe File…", systemImage: "document")
                        }
                        Button(action: {
                            viewModel.showHTMLExportSettings()
                        }) {
                            Label("Export as HTML…", systemImage: "text.page")
                        }
                        if let recipeId = viewModel.selectedRecipeIDs.first,
                           let recipe = viewModel.recipes.first(where: { $0.id == recipeId }),
                           let shareableRecipe = viewModel.shareableRecipe(for: recipe) {
                            // Would like this to work with plain text fallback, but can't get to...
                            // ShareLink(item: shareableRecipe,
                            //           subject: Text("Shared with you from Salty Recipe Manager: \(recipe.name)"),
                            //           message: Text(shareableRecipe.plainTextRepresentation),
                            //           preview: SharePreview(recipe.name, image: createXPImage(recipe.imageThumbnailData ?? Data()))
                            // )
                            ShareLink(item: shareableRecipe.plainTextRepresentation + "\n\nShared from Salty Recipe Manager for iOS and macOS",
                                      subject: Text("Shared with you from Salty Recipe Manager: \(recipe.name)"),
                                      message: Text(shareableRecipe.plainTextRepresentation),
                                      preview: SharePreview(recipe.name, image: createXPImage(recipe.imageThumbnailData ?? Data()))
                            )
                            .disabled(viewModel.selectedRecipeIDs.isEmpty)
                        }
                        
                    } label: {
                        Label("Share or Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.selectedRecipeIDs.isEmpty)
                    
                    
                    Toggle(isOn: $viewModel.isFavoritesFilterActive) {
                        let imageName: String = isLiquidGlassAvailable() ?
                        "line.3.horizontal.decrease" :
                        (viewModel.isFavoritesFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        Label("Filter (Favorites Only)", systemImage: imageName)
                        // Needed to make look correcton macOS 15; removing is fine for macOS 26, but simulating same behavior for now as long as supporting both:
                           .foregroundStyle(viewModel.isFavoritesFilterActive
                                            ? AnyShapeStyle(isLiquidGlassAvailable() ? Color.white : Color.accentColor)
                                            : AnyShapeStyle(.foreground))
                    }
                    
                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete Recipe", systemImage: "trash")
                    }
                    .disabled(viewModel.selectedRecipeIDs.isEmpty)
                    
                    Menu {
                        Button(action: {
                            viewModel.addNewRecipe()
                        }) {
                            Label("New Recipe", systemImage: "plus")
                        }
                        Divider()
                        Button("Create from Web…") {
                            openWindow(id: "create-recipe-from-web-window")
                        }
                        .disabled(isAnySheetShown)
                        Button("Create from Image…") {
                            openWindow(id: "create-recipe-from-image-window")
                        }
                        Button("Import from File…") {
                            showingImportFromFileSheet = true
                        }
                        .disabled(isAnySheetShown)
                    } label: {
                        Label("New Recipe", systemImage: "plus")
                    }
                    primaryAction: {
                        viewModel.addNewRecipe()
                    }
                    
                }
                #endif
            }
            .alert("Delete Recipe\(viewModel.selectedRecipeIDs.count == 1 ? "" : "s")?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteSelectedRecipes() }
                    #if !os(macOS)
                    // Delay exiting edit mode to let deletion animation complete
                    Task {
                        try? await Task.sleep(for: .seconds(0.4))
                        isEditMode = false
                    }
                    #endif
                }
            } message: {
                Text("Are you sure you want to delete \(viewModel.selectedRecipeIDs.count) recipe\(viewModel.selectedRecipeIDs.count == 1 ? "" : "s")? This action cannot be undone.")
            }
            .fileExporter(
                isPresented: $viewModel.showingExportSheet,
                document: ExportDocument(data: viewModel.exportData ?? Data(), suggestedName: viewModel.exportFileName, contentType: viewModel.exportContentType),
                contentType: viewModel.exportContentType,
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
            .alert("Welcome to Salty!", isPresented: $showingFirstLaunchAlert) {
                Button("Import Sample Recipes") {
                    importSampleRecipes()
                }
                Button("Skip", role: .cancel) {
                    offeredSampleImport = true
                }
            } message: {
                Text("Would you like to import some sample recipes to get started? (Skip to start with empty recipe library.)")
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
                Group {
                    if useWebRecipeDetailView {
                        RecipeDetailWebView(recipe: recipe)
                    } else {
                        RecipeDetailView(recipe: recipe, onScaledRecipeSaved: viewModel.handleNewRecipeSaved)
                    }
                }
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
        .sheet(isPresented: $showingCreateFromImageSheet) {
            CreateRecipeFromImageView()
            #if os(macOS)
                .frame(minWidth: 800, minHeight: 700)
            #endif
        }
        #if !os(macOS)
        // Show full screen cover on iOS; macOS will use window instead
        .fullScreenCover(isPresented: $showingCreateFromWebSheet) {
            CreateRecipeFromWebView()
        }
        #endif
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
        .onReceive(NotificationCenter.default.publisher(for: .exportSelectedRecipesAsHTML)) { _ in
            viewModel.showHTMLExportSettings()
        }
        .sheet(isPresented: $viewModel.showingHTMLExportSettings) {
            HTMLExportSettingsView(options: $viewModel.htmlExportOptions) {
                viewModel.performHTMLExport()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .printSelectedRecipes)) { _ in
            viewModel.printSelectedRecipes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showImportFromFileSheet)) { _ in
            showingImportFromFileSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCreateFromWebSheet)) { _ in
            showingCreateFromWebSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showRecipeInfoInspector)) { _ in
            if let recipeId = viewModel.selectedRecipeIDs.first {
                recipeIDForInspector = recipeId
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .openSelectedRecipesInNewWindows)) { _ in
            openSelectedRecipesInNewWindows()
        }
        #endif
        .onChange(of: viewModel.selectedRecipeIDs) { _, _ in
            postRecipeSelectionChanged()
        }
        .onChange(of: isAnySheetShown) { _, _ in
            notifySheetStateChanged()
        }
        .onAppear {
            // Set up initial state after the view appears
            viewModel.setupInitialState()
            
            // For new launches on iPad/iPhone, show both sidebar and content
            if viewModel.isNewLaunch {
                columnVisibility = .all
            }
            
            // Check for first launch and show sample import alert if needed
            if !offeredSampleImport {
                showingFirstLaunchAlert = true
            }
            
            // Set to true after successful view load
            offeredSampleImport = true
            
            // Notify menu about initial selection state
            postRecipeSelectionChanged()
        }
    }
    
    // Helper to create a binding for a search option with validation
    // Shared implementation with Menus.swift
    private func binding(for option: RecipeListSearchOptions) -> Binding<Bool> {
        Binding(
            get: {
                searchOptionsTracker.isSelected(option)
            },
            set: { newValue in
                searchOptionsTracker.setSelected(option, newValue)
            }
        )
    }
    
    #if os(macOS)
    @ViewBuilder
    private func contextMenuForSelection(_ selectedIDs: Set<String>) -> some View {
        if selectedIDs.count == 1,
           let recipeId = selectedIDs.first,
           let recipe = viewModel.recipes.first(where: { $0.id == recipeId }) {
            contextMenuForSingleRecipe(recipe)
        } else if selectedIDs.count > 1 {
            contextMenuForMultipleRecipes()
        }
    }
    
    @ViewBuilder
    private func contextMenuForSingleRecipe(_ recipe: Recipe) -> some View {
        Button("Open Recipe in New Window", systemImage: "macwindow") {
            openRecipeInNewWindow(recipeId: recipe.id)
        }
        .keyboardShortcut(.return)
        Button("Edit", systemImage: "pencil") {
            viewModel.recipeToEditID = recipe.id
            viewModel.showingEditSheet = true
        }
        Menu("Export…") {
            Button("Export as Recipe File…") {
                viewModel.exportRecipe(recipe.id)
            }
            Button("Export as HTML…") {
                viewModel.showHTMLExportSettingsForRecipe(recipe.id)
            }
        }
        Button(role: .destructive, action: {
            Task { await viewModel.deleteRecipe(id: recipe.id) }
        }) {
            Label("Delete", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        Divider()
        Button("Get Info", systemImage: "info.circle") {
            recipeIDForInspector = recipe.id
        }
    }
    
    @ViewBuilder
    private func contextMenuForMultipleRecipes() -> some View {
        Button("Open Recipes in New Windows", systemImage: "macwindow") {
            openSelectedRecipesInNewWindows()
        }
        .keyboardShortcut(.return)
        Menu("Export…") {
            Button("Export as Recipe File…") {
                viewModel.exportSelectedRecipes()
            }
            Button("Export as HTML…") {
                viewModel.showHTMLExportSettings()
            }
        }
        Button(role: .destructive, action: {
            showingDeleteConfirmation = true
        }) {
            Label("Delete", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: [.command])
    }
    #endif
    
    @ViewBuilder
    private func contextMenuForRecipe(_ recipe: Recipe) -> some View {
        Button("Edit", systemImage: "pencil") {
            viewModel.recipeToEditID = recipe.id
            viewModel.showingEditSheet = true
        }
        Menu("Export…") {
            Button("Export as Recipe File…") {
                if viewModel.selectedRecipeIDs.count > 1 {
                    viewModel.exportSelectedRecipes()
                } else {
                    viewModel.exportRecipe(recipe.id)
                }
            }
            Button("Export as HTML…") {
                if viewModel.selectedRecipeIDs.count > 1 {
                    viewModel.showHTMLExportSettings()
                } else {
                    viewModel.showHTMLExportSettingsForRecipe(recipe.id)
                }
            }
            #if !os(macOS)
                // Putting here (iOS only) since can't seem to get to show on share sheet, but could be addressed in future:
                Button(action: {
                    viewModel.printRecipe(by: recipe.id)
                }) {
                    Label("Print…", systemImage: "printer")
                }
            #endif
        }
        #if !os(macOS)
        // Is in toolbar on macOS, but keep in context menu on iOS:
        Group {
            if let shareableRecipe = viewModel.shareableRecipe(for: recipe) {
                ShareLink(item: shareableRecipe,
                          subject: Text("Shared with you from Salty Recipe Manager: \(recipe.name)"),
                          message: Text(shareableRecipe.plainTextRepresentation),
                          preview: SharePreview(recipe.name, image: createXPImage(recipe.imageThumbnailData ?? Data()))
                )
            }
        }
        #endif
        Button(role: .destructive, action: {
            // Delete all selected recipes with prompt via same technique as menu item; or single recipe directly
            if viewModel.selectedRecipeIDs.count > 1 {
                showingDeleteConfirmation = true
            } else {
                Task { await viewModel.deleteRecipe(id: recipe.id) }
            }
        }) {
            Label("Delete", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        Divider()
        Button("Get Info", systemImage: "info.circle") {
            recipeIDForInspector = recipe.id
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
    static var readableContentTypes: [UTType] { [.saltyRecipe, .html] }
    
    var data: Data
    var suggestedName: String
    var contentType: UTType
    
    init(data: Data, suggestedName: String = "recipe", contentType: UTType = .saltyRecipe) {
        self.data = data
        self.suggestedName = suggestedName
        self.contentType = contentType
    }
    
    init(configuration: ReadConfiguration) throws {
        data = Data()
        suggestedName = "recipe"
        contentType = .saltyRecipe
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}


// MARK: - Inspector View

private struct RecipeInfoInspectorView: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.name)
                .font(.headline)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Created")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(recipe.createdDate.formatted(date: .abbreviated, time: .shortened))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Last Modified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(recipe.lastModifiedDate.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .padding()
    }
}





