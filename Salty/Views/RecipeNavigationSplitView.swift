// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

//
//  RecipeNavigationSplitView.swift
//  Salty
//
//  Created by Robert on 10/25/22, substantial re-creations on 7/24/23 and 6/10/25
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers
import SaltyCore
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

private struct DropTargetBackground: View {
    var body: some View {
        Color.accentColor
            .clipShape(.rect(cornerRadius: 5))
            .opacity(0.15)
            .padding(.horizontal, 10)
    }
}

private struct CategoryDropTargetView: View {
    let category: Category
    let viewModel: RecipeNavigationSplitViewModel
    @State private var isTargeted = false

    var body: some View {
        Label(category.name, systemImage: "rectangle.stack")
            .tag(SidebarItem.category(category.id))
            .dropDestination(for: String.self) { recipeIds, location in
                for recipeId in recipeIds {
                    Task { await viewModel.addRecipeToCategory(recipeId: recipeId, categoryId: category.id) }
                }
                return !recipeIds.isEmpty
            } isTargeted: { hovering in
                isTargeted = hovering
            }
            .modifier(ConditionalListRowBackground(isTargeted: isTargeted, background: DropTargetBackground()))
    }
}

private struct TagDropTargetView: View {
    let tag: Tag
    let viewModel: RecipeNavigationSplitViewModel
    @State private var isTargeted = false

    var body: some View {
        Label(tag.name, systemImage: "tag")
            .tag(SidebarItem.tag(tag.id))
            .dropDestination(for: String.self) { recipeIds, location in
                for recipeId in recipeIds {
                    Task { await viewModel.addRecipeToTag(recipeId: recipeId, tagId: tag.id) }
                }
                return !recipeIds.isEmpty
            } isTargeted: { hovering in
                isTargeted = hovering
            }
            .modifier(ConditionalListRowBackground(isTargeted: isTargeted, background: DropTargetBackground()))
    }
}

// MARK: - Root Split View

struct RecipeNavigationSplitView: View {
    // Received from MainView (which owns it via @State). @Bindable provides the `$viewModel`
    // bindings this view needs without taking a second, competing ownership of the instance.
    @Bindable var viewModel: RecipeNavigationSplitViewModel
    @AppStorage("offeredSampleImport") private var offeredSampleImport = false
    // To force for testing:
    //@State private var offeredSampleImport = false

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    @State private var showRecipeDetailOnly = false  // when true, shows detail view (third column) only for better recipe viewing
    // Layout to restore when leaving detail-only mode, captured on entry.
    @State private var columnVisibilityBeforeDetailOnly: NavigationSplitViewVisibility = .automatic
    // Tracking separately from showRecipeDetailOnly so can toggle this a tad before and avoid double animation (see add'l comments below):
    @State private var removeSidebarToggle = false
    @State private var showingEditLibCategoriesSheet = false
    @State private var showingEditLibTagsSheet = false
    @State private var showingEditLibCoursesSheet = false
    @State private var showingImportFromFileSheet = false
    @State private var showingCreateFromImageSheet = false
    @State private var showingCreateFromWebSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingDuplicateRecipesSheet = false
    @State private var showingConsolidateDuplicatesSheet = false
    @State private var showingFirstLaunchAlert = false

    private var isAnySheetShown: Bool {
        showingEditLibCategoriesSheet ||
        showingEditLibTagsSheet ||
        showingEditLibCoursesSheet ||
        showingImportFromFileSheet ||
        showingCreateFromImageSheet ||
        showingCreateFromWebSheet ||
        showingSettingsSheet ||
        showingDuplicateRecipesSheet ||
        showingConsolidateDuplicatesSheet
    }

    private func notifySheetStateChanged() {
        NotificationCenter.default.post(
            name: .sheetStateChanged,
            object: nil,
            userInfo: ["isShown": isAnySheetShown]
        )
    }

    /// Everything the menu bar derives from the selection, in one Equatable value.
    ///
    /// One `onChange` rather than two: the menus need re-posting both when the selection moves (count,
    /// enablement) and when the Last Prepared value changes under a stable selection (mark a recipe made
    /// and the heading should follow). Keyed on this short string rather than on `viewModel.recipes` so
    /// the comparison doesn't walk every row's thumbnail blob — and so a selection swap that changes
    /// neither count nor date skips a post that would carry identical contents.
    private var recipeSelectionMenuState: String {
        "\(viewModel.selectedRecipeIDs.count)|\(viewModel.lastPreparedSummaryForSelection)"
    }

    private func postRecipeSelectionChanged() {
        let count = viewModel.selectedRecipeIDs.count
        NotificationCenter.default.post(
            name: .recipeSelectionChanged,
            object: nil,
            userInfo: [
                "hasSelected": count > 0,
                "count": count,
                // The menu bar's Last Prepared heading. Sent with the selection because that's the only
                // channel Commands can see, and re-sent on the value change below so marking a recipe
                // made refreshes the heading without the selection moving.
                "lastPreparedSummary": viewModel.lastPreparedSummaryForSelection,
            ]
        )
    }

    /// Entering detail-only mode hides the sidebar and recipe list so the recipe gets the full window,
    /// remembering the layout so leaving the mode restores it.
    private func applyDetailOnlyMode(_ detailOnly: Bool) {
        if detailOnly {
            // Seems to be oddidiy on at least iOS 26 (only version tested) where restoring .automatic
            // after .detailOnly  can come back as content plus detail with no sidebar toggle, making
            // restoration of it possible only via swipe gesture. Using .all instead of .automatic seems
            // to work around that, so will restore that value here in that case.
            columnVisibilityBeforeDetailOnly = columnVisibility == .automatic ? .all : columnVisibility
            removeSidebarToggle = true
            // Awkward workaround to avoid jitter while sidebar toggle icon removed, but works for now...
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                guard showRecipeDetailOnly else { return }
                withAnimation(.smooth) {
                    columnVisibility = .detailOnly
                }
            }
        } else {
            removeSidebarToggle = false
            // Only restore if still in detail-only; otherwise the user already picked a layout by hand.
            guard columnVisibility == .detailOnly else { return }
            // Same sequencing as entry, mirrored: let the toggle removal lift before the columns
            // animate. If the removal is still rendered while UIKit rebuilds the bars for the
            // restore, the system sidebar toggle is dropped and never comes back (verified).
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                guard !showRecipeDetailOnly else { return }
                withAnimation(.smooth) {
                    columnVisibility = columnVisibilityBeforeDetailOnly
                }
            }
        }
    }

    /// Bringing the columns back by hand (sidebar toggle, drag) exits detail-only mode,
    /// so the toolbar button's label stays in sync with what's on screen.
    private func exitDetailOnlyModeIfColumnsRestored(_ newVisibility: NavigationSplitViewVisibility) {
        if showRecipeDetailOnly && newVisibility != .detailOnly {
            showRecipeDetailOnly = false
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if removeSidebarToggle {
                SidebarColumnView(
                    viewModel: viewModel,
                    showingSettingsSheet: $showingSettingsSheet
                )
                .toolbar(removing: .sidebarToggle) // reduntant with arrows toolbar icon, so removing (only) if detail view expanded to full
            } else {
                SidebarColumnView(
                    viewModel: viewModel,
                    showingSettingsSheet: $showingSettingsSheet
                )
            }
        } content: {
            if viewModel.selectedSidebarItem?.isShoppingLists == true {
                ShoppingListsListView(viewModel: viewModel)
            } else {
                RecipeListColumnView(
                    viewModel: viewModel,
                    isAnySheetShown: isAnySheetShown,
                    showingImportFromFileSheet: $showingImportFromFileSheet,
                    showingCreateFromImageSheet: $showingCreateFromImageSheet,
                    showingCreateFromWebSheet: $showingCreateFromWebSheet,
                    showingSettingsSheet: $showingSettingsSheet,
                    showingEditLibCategoriesSheet: $showingEditLibCategoriesSheet,
                    showingEditLibTagsSheet: $showingEditLibTagsSheet,
                    showingEditLibCoursesSheet: $showingEditLibCoursesSheet,
                    showingDuplicateRecipesSheet: $showingDuplicateRecipesSheet,
                    showingConsolidateDuplicatesSheet: $showingConsolidateDuplicatesSheet
                )
            }
        } detail: {
            RecipeDetailColumnView(
                viewModel: viewModel,
                showRecipeDetailOnly: $showRecipeDetailOnly
            )
        }
        .navigationTitle("Recipes")
        .modifier(RootPresentationsModifier(
            viewModel: viewModel,
            showingImportFromFileSheet: $showingImportFromFileSheet,
            showingCreateFromImageSheet: $showingCreateFromImageSheet,
            showingCreateFromWebSheet: $showingCreateFromWebSheet,
            showingEditLibCategoriesSheet: $showingEditLibCategoriesSheet,
            showingEditLibTagsSheet: $showingEditLibTagsSheet,
            showingEditLibCoursesSheet: $showingEditLibCoursesSheet,
            showingSettingsSheet: $showingSettingsSheet,
            showingDuplicateRecipesSheet: $showingDuplicateRecipesSheet,
            showingConsolidateDuplicatesSheet: $showingConsolidateDuplicatesSheet,
            showingFirstLaunchAlert: $showingFirstLaunchAlert
        ))
        .onReceive(NotificationCenter.default.publisher(for: .createNewRecipe)) { _ in
            viewModel.addNewRecipe()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDuplicateRecipes)) { _ in
            showingDuplicateRecipesSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showConsolidateDuplicates)) { _ in
            showingConsolidateDuplicatesSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSelectedRecipes)) { _ in
            viewModel.exportSelectedRecipes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSelectedRecipesAsHTML)) { _ in
            viewModel.showHTMLExportSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSelectedRecipesAsJSONLD)) { _ in
            viewModel.exportSelectedRecipesAsJSONLD()
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
        .onReceive(NotificationCenter.default.publisher(for: .recipeImportedFromWeb)) { notification in
            if let recipeId = notification.userInfo?["recipeId"] as? String {
                viewModel.handleNewRecipeSaved(recipeId: recipeId)
            }
        }
        .onChange(of: recipeSelectionMenuState) { _, _ in
            postRecipeSelectionChanged()
        }
        .onChange(of: isAnySheetShown) { _, _ in
            notifySheetStateChanged()
        }
        .onChange(of: showRecipeDetailOnly) { _, detailOnly in
            applyDetailOnlyMode(detailOnly)
        }
        .onChange(of: columnVisibility) { _, newVisibility in
            exitDetailOnlyModeIfColumnsRestored(newVisibility)
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
}

// MARK: - Sidebar Column

private struct SidebarColumnView: View {
    @Bindable var viewModel: RecipeNavigationSplitViewModel
    @Binding var showingSettingsSheet: Bool

    @AppStorage("sidebarShowFavorites") private var showFavorites = true
    @AppStorage("sidebarShowWantToMake") private var showWantToMake = true
    @AppStorage("sidebarShowCategories") private var showCategories = true
    @AppStorage("sidebarShowCourses") private var showCourses = true
    @AppStorage("sidebarShowTags") private var showTags = true
    @AppStorage("sidebarShowShoppingLists") private var showShoppingLists = true
    // Order of the sections below Library, set in General settings.
    @AppStorage(SidebarSectionOrder.storageKey) private var sectionOrderRaw = ""
    @AppStorage("sidebarExpandCategories") private var expandCategories = true
    @AppStorage("sidebarExpandCourses") private var expandCourses = true
    @AppStorage("sidebarExpandTags") private var expandTags = true

    /// One of the reorderable sidebar sections. Hidden sections build to nothing, so the list simply skips
    /// them while they keep their place in the stored order.
    @ViewBuilder
    private func sidebarSection(_ section: SidebarSection) -> some View {
        switch section {
        case .categories:
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
        case .courses:
            if showCourses {
                Section(isExpanded: $expandCourses) {
                    ForEach(viewModel.courses) { course in
                        Label(course.name, systemImage: "fork.knife")
                            .tag(SidebarItem.course(course.id))
                    }
                } header: {
                    Text("Courses")
                }
            }
        case .tags:
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
        case .shoppingLists:
            if showShoppingLists {
                Section {
                    Label("All Lists", systemImage: "cart")
                        .tag(SidebarItem.allShoppingLists)
                } header: {
                    Text("Shopping Lists")
                }
            }
        }
    }

    /// Hiding a section while one of its rows is selected would leave the selection pointing at a row
    /// that's no longer in the sidebar, so fall back to All Recipes.
    private func restoreSelectionIfHidden(_ section: SidebarSection, isShown: Bool) {
        guard !isShown, viewModel.selectedSidebarItem?.sidebarSection == section else { return }
        viewModel.selectedSidebarItem = .allRecipes
    }

    var body: some View {
        List(selection: $viewModel.selectedSidebarItem) {
            // Library:
            Section {
                Label("All Recipes", systemImage: "book")
                    .tag(SidebarItem.allRecipes)
                if showFavorites {
                    Label("Favorites", systemImage: "heart")
                        .tag(SidebarItem.favorites)
                }
                if showWantToMake {
                    Label("Want to Make", systemImage: "bookmark")
                        .tag(SidebarItem.wantToMake)
                }
            } header: {
                Text("Library")
            }

            // Everything below Library, in the order and with the visibility set in General settings.
            ForEach(SidebarSectionOrder.decode(sectionOrderRaw)) { section in
                sidebarSection(section)
            }
//            // Smart Lists:
//            Section {
//                Text("Coming Soon")
//            } header: {
//                Text("Smart Lists")
//            }
            #if !os(macOS)
            // Photos-style status at the end of the sidebar -- visible at the root on iPhone,
            // where the recipe list's toolbar isn't. Tapping it (or pulling down) syncs now.
            Section {
                SyncStatusFooterView()
            }
            #endif
        }
        .listStyle(.sidebar)
        #if !os(macOS)
        .refreshable { await ManualSyncRunner.shared.sync() }
        // Settings from the sidebar root, leading like Mail's sidebar Edit button: the gear is
        // the only route to the sync UI when the recipe-list column (and its "More" menu) is
        // off screen. Library maintenance intentionally stays on the recipe-list menu only.
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        #endif
        #if os(macOS)
        .onAppear() {
            // On macOS, set default selection to "All Recipes" if no selection exists
            if viewModel.selectedSidebarItem == nil {
                viewModel.selectedSidebarItem = .allRecipes
            }
        }
        #endif
        // If the user hides a smart list that's currently selected, fall back to All Recipes so the
        // selection never points at a row that's no longer in the sidebar.
        .onChange(of: showFavorites) { _, isShown in
            if !isShown, viewModel.selectedSidebarItem == .favorites {
                viewModel.selectedSidebarItem = .allRecipes
            }
        }
        .onChange(of: showWantToMake) { _, isShown in
            if !isShown, viewModel.selectedSidebarItem == .wantToMake {
                viewModel.selectedSidebarItem = .allRecipes
            }
        }
        .onChange(of: showCategories) { _, isShown in
            restoreSelectionIfHidden(.categories, isShown: isShown)
        }
        .onChange(of: showCourses) { _, isShown in
            restoreSelectionIfHidden(.courses, isShown: isShown)
        }
        .onChange(of: showTags) { _, isShown in
            restoreSelectionIfHidden(.tags, isShown: isShown)
        }
        .onChange(of: showShoppingLists) { _, isShown in
            restoreSelectionIfHidden(.shoppingLists, isShown: isShown)
        }
    }
}

// MARK: - Recipe List Column

private struct RecipeListColumnView: View {
    @Bindable var viewModel: RecipeNavigationSplitViewModel
    let isAnySheetShown: Bool
    @Binding var showingImportFromFileSheet: Bool
    @Binding var showingCreateFromImageSheet: Bool
    @Binding var showingCreateFromWebSheet: Bool
    @Binding var showingSettingsSheet: Bool
    @Binding var showingEditLibCategoriesSheet: Bool
    @Binding var showingEditLibTagsSheet: Bool
    @Binding var showingEditLibCoursesSheet: Bool
    @Binding var showingDuplicateRecipesSheet: Bool
    @Binding var showingConsolidateDuplicatesSheet: Bool

    @Environment(\.openWindow) private var openWindow
    @State private var searchOptionsTracker = SearchOptionsTracker()
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isEditMode = false
    @State private var showingDeleteConfirmation = false
    @State private var recipeIDForInspector: String? = nil
    /// Recipes awaiting a custom "last made" date, and the date being picked. Non-nil `lastMadePickerDate`
    /// drives the sheet, so the two are set together when "Set Date…" is chosen.
    @State private var lastMadeTargetIDs: [String] = []
    @State private var lastMadePickerDate: Date? = nil
    private let logger = Logger(subsystem: "Salty", category: "UI")

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

    /// Library maintenance submenu on the recipe-list "More" menu on iOS.
    /// (macOS offers the same items from the menu bar instead.)
    @ViewBuilder
    private var libraryMenu: some View {
        Menu("Library", systemImage: "books.vertical") {
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
            Button("Show Duplicate Recipes…") {
                showingDuplicateRecipesSheet = true
            }
            Button("Consolidate Duplicate Categories, Courses, and Tags…") {
                showingConsolidateDuplicatesSheet = true
            }
        }
    }

    /// Scrolls the list to a newly added recipe once its row actually exists.
    ///
    /// The row can't be scrolled to right away; the database write has to propagate through
    /// `@FetchAll`, and when the sidebar selection also changed (as it does after an import) the
    /// list query is re-issued and reloaded asynchronously. Wait for the row to appear (replaces old
    /// awkward, fixed-delay workaround).
    private func scrollToNewRecipe(id: String, proxy: ScrollViewProxy) async {
        guard await waitForSettledRecipeRow(id: id) else {
            logger.warning("Recipe \(id) did not appear in the list; skipped scrolling to this recipe.")
            return
        }

        // Multiple scroll tries since seems to not make it all the way to item if at bottom of large
        // list, possibly as view stil builds row. Make animation short (but present) for first try,
        // instant for later "catch-ups" if needed.
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .center)
        }
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(250))
            proxy.scrollTo(id, anchor: .center)
        }
    }

    /// Waits for the new recipe's row to appear *and* for the list contents to stop changing, so the
    /// scroll isn't issued against a list that is still swapping in the results of a reloaded query.
    /// Returns false if the row never showed up.
    private func waitForSettledRecipeRow(id: String) async -> Bool {
        let pollInterval = Duration.milliseconds(50)
        let maxAttempts = 100 // ~5 seconds
        let requiredStablePolls = 3
        var stablePolls = 0
        var lastCount = -1

        for _ in 0..<maxAttempts {
            let currentRecipes = viewModel.recipes
            let containsRow = currentRecipes.contains { $0.id == id }
            stablePolls = (containsRow && currentRecipes.count == lastCount) ? stablePolls + 1 : 0
            lastCount = currentRecipes.count

            if stablePolls >= requiredStablePolls {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }

        return false
    }

    private var recipeQueryId: String {
        // Include search options in the query ID so changes trigger refresh
        // Use the tracker's changeId to force update when search options change
        let searchOptionsKey = RecipeListSearchOptions.allCases
            .map { UserDefaults.standard.bool(forKey: $0.userDefaultsKey) ? "1" : "0" }
            .joined(separator: "")
        return "\(viewModel.searchString)||\(viewModel.selectedSidebarItem?.queryKey ?? "")||\(viewModel.isFavoritesFilterActive)||\(viewModel.recipeListSortOrder.rawValue)||\(viewModel.recipeListSortDirection.rawValue)||\(searchOptionsKey)||\(searchOptionsTracker.changeId.uuidString)"
    }

    var body: some View {
        // ScrollViewReader (rather than ScrollPosition, preferred elsewhere in the app) because
        // `ScrollPosition.scrollTo(id:)` only scrolls to views registered as scroll targets via
        // `.scrollTargetLayout()`, which a `List` has no way to apply — so it silently does nothing
        // here. `scrollTo(edge:)` works on a List (see the library editors), but scrolling to a
        // specific row needs the proxy.
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
                            recipeContextMenu(for: recipe)
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
            }
            .onChange(of: viewModel.shouldScrollToNewRecipe) { _, shouldScroll in
                guard shouldScroll, let newId = viewModel.selectedRecipeIDs.first else { return }
                // Reset the flag so a later addition can trigger another scroll
                viewModel.shouldScrollToNewRecipe = false
                Task { await scrollToNewRecipe(id: newId, proxy: proxy) }
            }
        }
        .overlay {
            // As an overlay rather than a list row, so it centers in the column instead of
            // sitting at the top like a cell.
            if viewModel.recipes.isEmpty && viewModel.selectedSidebarItem != .allRecipes {
                if viewModel.searchString.isEmpty {
                    ContentUnavailableView("No Recipes", systemImage: "list.bullet.rectangle",
                                           description: Text("Recipes matching the selected criteria will appear here."))
                } else {
                    ContentUnavailableView.search(text: viewModel.searchString)
                }
            }
            else if viewModel.recipes.isEmpty {
                if viewModel.searchString.isEmpty {
                    ContentUnavailableView("No Recipes", systemImage: "list.bullet.rectangle",
                                           description: Text("Recipes you add to your recipe library will appear here."))
                } else {
                    ContentUnavailableView.search(text: viewModel.searchString)
                }
            }
        }
        #if os(macOS)
        .contextMenu(forSelectionType: String.self) { selectedIDs in
            contextMenuForSelection(selectedIDs)
        } primaryAction: { selectedIDs in
            openSelectedRecipesInNewWindows(recipeIds: selectedIDs)
        }
        #endif
        .sheet(isPresented: Binding(
            get: { lastMadePickerDate != nil },
            set: { if !$0 { lastMadePickerDate = nil } }
        )) {
            LastMadeDatePickerSheet(
                date: lastMadePickerDate ?? Date(),
                recipeCount: lastMadeTargetIDs.count,
                onCancel: { lastMadePickerDate = nil },
                onSave: { picked in
                    let ids = lastMadeTargetIDs
                    lastMadePickerDate = nil
                    Task {
                        await viewModel.setLastMade(
                            RecipeNavigationSplitViewModel.localNoon(on: picked),
                            forRecipeIds: ids
                        )
                    }
                }
            )
        }
        // This sheet lives in the list column, not the outer view that owns `isAnySheetShown`, so it
        // reports its own state — otherwise the menu bar would still offer commands that open a second
        // sheet while the picker is up.
        .onChange(of: lastMadePickerDate) { _, date in
            NotificationCenter.default.post(
                name: .sheetStateChanged,
                object: nil,
                userInfo: ["isShown": date != nil]
            )
        }
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
                    libraryMenu

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
                    if let recipeId = viewModel.selectedRecipeIDs.first,
                       let recipe = viewModel.fullRecipe(id: recipeId),
                       let shareableRecipe = viewModel.shareableRecipe(for: recipe) {
                        // Would like this to work with plain text fallback, but can't get to...
                        // ShareLink(item: shareableRecipe,
                        //           subject: Text("Shared with you from Salty Recipe Manager: \(recipe.name)"),
                        //           message: Text(shareableRecipe.plainTextRepresentation),
                        //           preview: SharePreview(recipe.name, image: createXPImage(recipe.imageThumbnailData ?? Data()))
                        // )
                        ShareLink(item: shareableRecipe,
                                  subject: Text("Shared with you from Salty Recipe Manager: \(recipe.name)"),
                                  message: Text(shareableRecipe.plainTextRepresentation),
                                  preview: SharePreview(recipe.name, image: createXPImage(recipe.imageThumbnailData ?? Data()))
                        )
                        .disabled(viewModel.selectedRecipeIDs.isEmpty)
                    }
                    Divider()
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
                    Button(action: {
                        viewModel.exportSelectedRecipesAsJSONLD()
                    }) {
                        Label("Export as Schema.org JSON-LD…", systemImage: "curlybraces")
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
        #if os(macOS)
        .onDeleteCommand {
            if !viewModel.selectedRecipeIDs.isEmpty {
                showingDeleteConfirmation = true
            }
        }
        #endif
        .searchable(text: $viewModel.searchString)
        .searchFocused($isSearchFieldFocused)
        // Edit ▸ Find (⌘F) lands here. Scene-scoped, so only the frontmost window showing the
        // recipe list responds.
        .focusedSceneValue(\.searchFieldFocusAction, SearchFieldFocusAction { isSearchFieldFocused = true })
        #if !os(macOS)
        .refreshable { await ManualSyncRunner.shared.sync() }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .showRecipeInfoInspector)) { _ in
            if let recipeId = viewModel.selectedRecipeIDs.first {
                recipeIDForInspector = recipeId
            }
        }
        // "Last Made" from the menu bar, applied to the whole selection like the other selection commands.
        // The menu items are already disabled without a selection; the guards keep a stray post harmless.
        .onReceive(NotificationCenter.default.publisher(for: .markSelectedRecipesMadeToday)) { _ in
            let ids = Array(viewModel.selectedRecipeIDs)
            guard !ids.isEmpty else { return }
            Task { await viewModel.setLastMade(Date(), forRecipeIds: ids) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setSelectedRecipesLastMadeDate)) { _ in
            let ids = Array(viewModel.selectedRecipeIDs)
            guard !ids.isEmpty else { return }
            lastMadeTargetIDs = ids
            lastMadePickerDate = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearSelectedRecipesLastMade)) { _ in
            let ids = Array(viewModel.selectedRecipeIDs)
            guard !ids.isEmpty else { return }
            Task { await viewModel.setLastMade(nil, forRecipeIds: ids) }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .openSelectedRecipesInNewWindows)) { _ in
            openSelectedRecipesInNewWindows()
        }
        #endif
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
            recipeContextMenu(for: recipe)
        } else if selectedIDs.count > 1 {
            contextMenuForMultipleRecipes()
        }
    }

    @ViewBuilder
    private func contextMenuForMultipleRecipes() -> some View {
        Button("Open in New Windows", systemImage: "macwindow") {
            openSelectedRecipesInNewWindows()
        }
        .keyboardShortcut(.return)
        Menu("Export…") {
            recipeExportFormatItems(
                recipeFile: { viewModel.exportSelectedRecipes() },
                html: { viewModel.showHTMLExportSettings() },
                jsonLD: { viewModel.exportSelectedRecipesAsJSONLD() }
            )
        }
        lastMadeMenu(for: Array(viewModel.selectedRecipeIDs))
        Button(role: .destructive, action: {
            showingDeleteConfirmation = true
        }) {
            Label("Delete", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: [.command])
    }
    #endif

    /// "Last Made" submenu, shared by the single-recipe and multi-selection context menus. Setting a
    /// custom date opens the picker sheet, or "Clear" removes
    ///
    /// The section header states the current value, so the menu answers "when did I last make this?"
    /// without a detour through Get Info. A `Section` title -- not a disabled `Button` -- because this is
    /// a heading describing the group, whereas a greyed-out item reads as "a command you can't run now".
    @ViewBuilder
    private func lastMadeMenu(for recipeIds: [String]) -> some View {
        Menu("Last Prepared Date") {
            Section(viewModel.lastPreparedSummary(forRecipeIds: recipeIds)) {
                Button("Set to Today") {
                    Task { await viewModel.setLastMade(Date(), forRecipeIds: recipeIds) }
                }
                Button("Set as Date…") {
                    lastMadeTargetIDs = recipeIds
                    lastMadePickerDate = Date()
                }
                Divider()
                Button("Clear") {
                    Task { await viewModel.setLastMade(nil, forRecipeIds: recipeIds) }
                }
            }
        }
    }

    /// Single-recipe context menu, shared by the iOS list rows and the macOS selection menu. Identical
    /// on both platforms except for "Open in New Window" (macOS only).
    @ViewBuilder
    private func recipeContextMenu(for recipe: RecipeListItem) -> some View {
        #if os(macOS)
        Button("Open in New Window", systemImage: "macwindow") {
            openRecipeInNewWindow(recipeId: recipe.id)
        }
        .keyboardShortcut(.return)
        #endif

        Button("Edit", systemImage: "pencil") {

            viewModel.recipeToEditID = recipe.id
            viewModel.showingEditSheet = true
        }
        Button(role: .destructive) {
            Task { await viewModel.deleteRecipe(id: recipe.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        Divider()

        Menu("Export…") {
            recipeExportFormatItems(
                recipeFile: { viewModel.exportRecipe(recipe.id) },
                html: { viewModel.showHTMLExportSettingsForRecipe(recipe.id) },
                jsonLD: { viewModel.exportRecipeAsJSONLD(recipe.id) }
            )
        }

        if let fullRecipe = viewModel.fullRecipe(id: recipe.id),
           let shareableRecipe = viewModel.shareableRecipe(for: fullRecipe) {
            ShareLink(item: shareableRecipe,
                      subject: Text("Shared with you from Salty Recipe Manager: \(recipe.name)"),
                      message: Text(shareableRecipe.plainTextRepresentation),
                      preview: SharePreview(recipe.name, image: createXPImage(recipe.imageThumbnailData ?? Data()))
            )
        }

        Button("Print…", systemImage: "printer") {
            viewModel.printRecipe(by: recipe.id)
        }


        Divider()

        lastMadeMenu(for: [recipe.id])

        Button("Get Info", systemImage: "info.circle") {
            recipeIDForInspector = recipe.id
        }
    }
}

// MARK: - Detail Column

private struct RecipeDetailColumnView: View {
    @Bindable var viewModel: RecipeNavigationSplitViewModel
    @Binding var showRecipeDetailOnly: Bool
    @AppStorage("webPreviews") private var useWebRecipeDetailView = false
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private func editRecipe(_ recipeId: String) {
        viewModel.recipeToEditID = recipeId
        viewModel.showingEditSheet = true
    }

    var body: some View {
        if viewModel.selectedSidebarItem?.isShoppingLists == true {
            // Currently, don't show preview if more than one selected:
            if viewModel.selectedShoppingListIDs.count == 1,
               let listId = viewModel.selectedShoppingListIDs.first,
               let list = viewModel.shoppingLists.first(where: { $0.id == listId }) {
                Group {
                    if list.isFreeform {
                        ShoppingListFreeformView(listId: listId)
                    } else {
                        ShoppingListDetailView(listId: listId)
                    }
                }
                .id(listId)
                .navigationTitle(list.name)
                #if os(macOS)
                .navigationSubtitle(list.isFreeform ? "Freeform List" : "Checklist")
                #endif
            } else {
                ContentUnavailableView("No List Selected", systemImage: "checklist")
            }
        } else if let recipeId = viewModel.selectedRecipeIDs.first,
            let recipe = viewModel.fullRecipe(id: recipeId) {
            Group {
                if useWebRecipeDetailView {
                    RecipeDetailWebView(recipe: recipe)
                        // The web preview has no Chef View button to order against, so it keeps
                        // declaring Edit itself. RecipeDetailView owns both in the other branch.
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Edit", systemImage: "pencil") { editRecipe(recipeId) }
                                    .keyboardShortcut("e", modifiers: .command)
                            }
                        }
                } else {
                    RecipeDetailView(
                        recipe: recipe,
                        // Handed down so Chef View and Edit are declared in one place, in the order
                        // that puts Edit on the outer edge. See RecipeDetailView.onEdit.
                        onEdit: { editRecipe(recipeId) },
                        onScaledRecipeSaved: viewModel.handleNewRecipeSaved
                    )
                }
            }
            .id(recipeId) // seems to be needed to force full reload when recipe changes?
            .toolbar {
            #if !os(macOS)
                if horizontalSizeClass == .regular {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            showRecipeDetailOnly.toggle()
                        }) {
                            Label(showRecipeDetailOnly ? "Show Recipes List" : "Hide Recipes List",
                                  systemImage: showRecipeDetailOnly ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        }
                    }
                }
            #endif
            }
        } else {
            ContentUnavailableView("No Recipe Selected", systemImage: "list.bullet.rectangle")
        }
    }
}

// MARK: - Root Presentations

/// Every sheet, cover, and alert presented from the split view's root, grouped so the root's
/// modifier chain stays within the compiler's type-checking limits. A `ViewModifier` rather than
/// a `View` struct because a bare modifier chain has no view of its own to wrap.
private struct RootPresentationsModifier: ViewModifier {
    @Bindable var viewModel: RecipeNavigationSplitViewModel
    @Binding var showingImportFromFileSheet: Bool
    @Binding var showingCreateFromImageSheet: Bool
    @Binding var showingCreateFromWebSheet: Bool
    @Binding var showingEditLibCategoriesSheet: Bool
    @Binding var showingEditLibTagsSheet: Bool
    @Binding var showingEditLibCoursesSheet: Bool
    @Binding var showingSettingsSheet: Bool
    @Binding var showingDuplicateRecipesSheet: Bool
    @Binding var showingConsolidateDuplicatesSheet: Bool
    @Binding var showingFirstLaunchAlert: Bool

    @AppStorage("offeredSampleImport") private var offeredSampleImport = false
    @State private var manualSync = ManualSyncRunner.shared

    /// Presents the shared sync-failure alert whenever ManualSyncRunner holds an error; dismissing clears it.
    private var showingSyncErrorAlert: Binding<Bool> {
        Binding(
            get: { manualSync.errorMessage != nil },
            set: { if !$0 { manualSync.errorMessage = nil } }
        )
    }

    private func importSampleRecipes() {
        Task {
            await viewModel.importSampleRecipes()
            await MainActor.run {
                offeredSampleImport = true
            }
        }
    }

    func body(content: Content) -> some View {
        content
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
        // Library maintenance (File ▸ Library on macOS, where both open in their own windows instead).
        .sheet(isPresented: $showingDuplicateRecipesSheet) {
            NavigationStack {
                DuplicateRecipesView()
            }
        }
        .sheet(isPresented: $showingConsolidateDuplicatesSheet) {
            NavigationStack {
                ConsolidateDuplicatesView()
            }
        }
        .sheet(isPresented: $viewModel.showingHTMLExportSettings) {
            HTMLExportSettingsView(options: $viewModel.htmlExportOptions) {
                viewModel.performHTMLExport()
            }
        }
        // One alert serves every lightweight sync trigger (pull-to-refresh, footer rows, menu command);
        // benign outcomes never set errorMessage, so this only appears for real failures.
        .alert("Sync Failed", isPresented: showingSyncErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(manualSync.errorMessage ?? "")
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
    }
}

#Preview {
    RecipeNavigationSplitView(
        viewModel: RecipeNavigationSplitViewModel()
    )
    .environment(ChefViewSessionStore())
}

// MARK: - Export Document

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.saltyRecipe, .html, .json] }

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

/// Date picker for "Last Prepared Date > Set as Date…". Offers current or past dates only.
///
/// Laid out per platform to get best button placement on each:
///
/// - **iOS/iPadOS** gets a real navigation bar (a `NavigationStack` inside the sheet). `.cancellationAction`
///   and `.confirmationAction` put Cancel and Save at opposite ends of the bar (or wherever platform decides).
/// - **macOS** keeps a bottom button row, which is the platform convention for a modal panel: default
///   action in the lower-right, Cancel to its left. Sharing picker between two platforms with these custom UIs for each.
private struct LastMadeDatePickerSheet: View {
    @State var date: Date
    let recipeCount: Int
    let onCancel: () -> Void
    let onSave: (Date) -> Void

    private static let title = "Set Last Prepared Date"

    /// Opening height of the iOS/iPadOS sheet: navigation bar + a six-row month + padding. Measured
    /// rather than derived — the graphical DatePicker won't report its size to the layout system (see
    /// the presentation modifiers below), so there's nothing to compute it from.
    private static let preferredSheetHeight: CGFloat = 520

    var body: some View {
        #if os(macOS)
        VStack(spacing: 16) {
            Text(Self.title)
                .font(.headline)
            // Intrinsic size, so the calendar doesn't stretch to fill a panel wider than it needs:
            picker.fixedSize()
            multipleRecipesNote
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(date) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        // No minimum width: the sheet hugs the calendar's own width instead of stretching past it, and
        // the default (centered) VStack alignment then centers the calendar rather than pinning it left.
        #else
        NavigationStack {
            // Scrolls only when it has to. A month with six rows plus a large Dynamic Type size can
            // out-grow the sheet on some devices; without this the last week is simply cut off and
            // unreachable, which is how the iPad sheet first went wrong.
            ScrollView {
                VStack(spacing: 12) {
                    // `.fixedSize(vertical:)` only: the calendar keeps its natural HEIGHT (so the scroll
                    // view can reveal all of it) while still taking the sheet's full width. Fixing the
                    // width too makes the iPhone sheet clip the right-hand columns.
                    picker.fixedSize(horizontal: false, vertical: true)
                    multipleRecipesNote
                }
                .padding(.horizontal)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(date) }
                }
            }
        }
        // Opens at a height sized for a calendar rather than `.medium`, which is a fraction of the screen
        // and left the month cut off on iPad until you dragged the sheet up. A six-row month (one that
        // starts on a Saturday) is the tall case this has to clear; `.large` stays in the list so the
        // sheet can still be expanded, and the ScrollView above covers anything taller still — a big
        // Dynamic Type size, say.
        .presentationDetents([.height(Self.preferredSheetHeight), .large])
        // iPad presents a centered card; `.form` gives it the standard form-sheet WIDTH (its default was
        // both too narrow and too short). Height comes from the detent above.
        //
        // Sizing-to-content reads like the better answer here and isn't: a graphical DatePicker inside a
        // NavigationStack reports no usable ideal size, so `.fitted` collapses the sheet to a pill and
        // `.form.fitted(vertical:)` collapses it to a bar — both verified on an iPad Air, with and without
        // a Spacer. Hence an explicit height.
        .presentationSizing(.form)
        #endif
    }

    private var picker: some View {
        DatePicker(
            Self.title,
            selection: $date,
            in: ...Date(),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
    }

    /// Multi-selection is invisible from a calendar alone, and this sheet overwrites every recipe it
    /// applies to — so say how many when it's more than one. Kept out of the title, which would grow
    /// awkwardly long in a navigation bar.
    @ViewBuilder
    private var multipleRecipesNote: some View {
        if recipeCount > 1 {
            Text("Applies to \(recipeCount) recipes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecipeInfoInspectorView: View {
    let recipe: RecipeListItem
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Last Prepared")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Date only since we don't care about time resolution (and "set as day" gets local noon so not always exact)
                if let lastPrepared = recipe.lastPrepared {
                    Text(lastPrepared.formatted(date: .abbreviated, time: .omitted))
                } else {
                    Text("Not set").foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
