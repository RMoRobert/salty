//
//  Menus.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import SwiftUI
import SaltyCore

// Want to disable some menu items on macOS (and iPadOS 26+?) when
// sheets are open since can't open more than one; this should help
@MainActor
@Observable
class SheetStateTracker {
    var isAnySheetShown = false

    init() {
        NotificationCenter.default.addObserver(
            forName: .sheetStateChanged,
            object: nil,
            queue: .main
        ) { notification in
            // Extract the Sendable value before hopping; Notification itself isn't Sendable.
            let isShown = notification.userInfo?["isShown"] as? Bool
            // Delivered on .main, so assume main-actor isolation to touch this @Observable safely.
            MainActor.assumeIsolated {
                if let isShown { self.isAnySheetShown = isShown }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// Track recipe selection state for enabling/disabling menu items
@MainActor
@Observable
class SelectionStateTracker {
    var hasRecipeSelected = false
    var selectedRecipeCount = 0
    /// Heading for the menu bar's "Last Prepared Date" menu. Computed by the view (which holds the
    /// recipe list) and pushed here, since Commands can't reach the view model. Re-posted when the
    /// value changes as well as when the selection does, so marking a recipe made updates the menu.
    var lastPreparedSummary = "Last Prepared"

    init() {
        NotificationCenter.default.addObserver(
            forName: .recipeSelectionChanged,
            object: nil,
            queue: .main
        ) { notification in
            // Extract the Sendable values before hopping; Notification itself isn't Sendable.
            let hasSelected = notification.userInfo?["hasSelected"] as? Bool
            let count = notification.userInfo?["count"] as? Int
            let summary = notification.userInfo?["lastPreparedSummary"] as? String
            // Delivered on .main, so assume main-actor isolation to touch this @Observable safely.
            MainActor.assumeIsolated {
                if let hasSelected { self.hasRecipeSelected = hasSelected }
                if let count { self.selectedRecipeCount = count }
                if let summary { self.lastPreparedSummary = summary }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// Track search options state to make menu reactive to UserDefaults changes
// Also tracks changes via changeId to trigger query updates
@MainActor
@Observable
class SearchOptionsTracker {
    // Private cache of the UserDefaults values; `changeId` is bumped whenever the selected options
    // change so dependents (e.g. the recipe query id) refresh.
    private var optionStates: [RecipeListSearchOptions: Bool] = [:]
    var changeId = UUID()
    private var lastSearchOptionsKey: String = ""

    init() {
        // Initialize from UserDefaults
        loadFromUserDefaults()
        lastSearchOptionsKey = currentSearchOptionsKey()

        // Observe UserDefaults changes
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on .main, so assume main-actor isolation to touch this @Observable safely.
            MainActor.assumeIsolated {
                self?.loadFromUserDefaults()
                self?.checkForChanges()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func loadFromUserDefaults() {
        for option in RecipeListSearchOptions.allCases {
            if UserDefaults.standard.object(forKey: option.userDefaultsKey) is Bool {
                optionStates[option] = UserDefaults.standard.bool(forKey: option.userDefaultsKey)
            } else {
                let defaultValue: Bool
                switch option {
                case .name:
                    defaultValue = true
                default:
                    defaultValue = false
                }
                UserDefaults.standard.set(defaultValue, forKey: option.userDefaultsKey)
                optionStates[option] = defaultValue
            }
        }
    }
    
    private func currentSearchOptionsKey() -> String {
        RecipeListSearchOptions.allCases
            .map { UserDefaults.standard.bool(forKey: $0.userDefaultsKey) ? "1" : "0" }
            .joined(separator: "")
    }
    
    private func checkForChanges() {
        let currentKey = currentSearchOptionsKey()
        // Only update if search options actually changed
        if currentKey != lastSearchOptionsKey {
            lastSearchOptionsKey = currentKey
            changeId = UUID()
        }
    }
    
    func isSelected(_ option: RecipeListSearchOptions) -> Bool {
        return optionStates[option] ?? (option == .name)
    }
    
    func setSelected(_ option: RecipeListSearchOptions, _ value: Bool) {
        if !value {
            // Check if this is the last selected option
            let otherOptions = RecipeListSearchOptions.allCases.filter { $0 != option }
            let anyOtherSelected = otherOptions.contains { isSelected($0) }
            if !anyOtherSelected {
                // Prevent unchecking if it's the last selected option
                return
            }
        }
        UserDefaults.standard.set(value, forKey: option.userDefaultsKey)
        optionStates[option] = value
        checkForChanges()
    }
}

struct Menus: Commands {
    @Environment(\.openWindow) private var openWindow
    @State private var sheetTracker = SheetStateTracker()
    @State private var selectionTracker = SelectionStateTracker()
    @State private var searchOptionsTracker = SearchOptionsTracker()
    @State private var syncService = SaltySyncService.shared
    /// The lists behind File ▸ Open Shopping List in New Window. Commands can't reach a scene's view
    /// model, so the menu does its own (tiny) fetch; see `ShoppingListsMenuModel`.
    @State private var shoppingListsMenu = ShoppingListsMenuModel()
    /// Non-nil only while a window showing the recipe list is frontmost; see `SearchFieldFocusAction`.
    @FocusedValue(\.searchFieldFocusAction) private var focusSearchField
    /// Non-nil only while a window showing a recipe is frontmost; see `ChefViewOpenAction`.
    @FocusedValue(\.chefViewOpenAction) private var openChefView
    /// Non-nil only while the web importer is frontmost; see `AddressFieldFocusAction`.
    @FocusedValue(\.addressFieldFocusAction) private var focusAddressField
    @AppStorage("serverUse") private var serverUse = false
    
    @AppStorage("recipeListSortOrder") private var recipeListSortOrder: RecipeListSortOrderSetting = .byName
    @AppStorage("recipeListSortDirection") private var recipeListSortDirection: RecipeListSortDirection = .ascending

    // Sidebar Items menu: the two fixed Library rows, plus the order the reorderable sections are listed in.
    @AppStorage("sidebarShowFavorites") private var showFavorites = true
    @AppStorage("sidebarShowWantToMake") private var showWantToMake = true
    @AppStorage(SidebarSectionOrder.storageKey) private var sidebarSectionOrderRaw = ""
    
    // Helper to create a binding for a search option with validation
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
    
    var body: some Commands {
       ToolbarCommands()
       SidebarCommands()
       // Replaces the stock "New Window" item so ⌘N can belong to New Recipe;
       // New Window is re-added below on ⇧⌘N.
       CommandGroup(replacing: .newItem) {
           Button("New Recipe") {
               NotificationCenter.default.post(name: .createNewRecipe, object: nil)
           }
           .disabled(sheetTracker.isAnySheetShown)
           .keyboardShortcut("n", modifiers: [.command])
           Button("New Recipe from Web…") {
               #if os(iOS)
               NotificationCenter.default.post(name: .showCreateFromWebSheet, object: nil)
               #else
               openWindow(id: "create-recipe-from-web-window")
               #endif
           }
           .disabled(sheetTracker.isAnySheetShown)
           .keyboardShortcut("n", modifiers: [.command, .option])
           Button("New Recipe from Image…") {
               openWindow(id: "create-recipe-from-image-window")
           }
           #if os(macOS)
           Button("New Window") {
               openWindow(id: "main-window")
           }
           .keyboardShortcut("n", modifiers: [.command, .shift])
           // Safari's File ▸ Open Location, and in the same menu. No ellipsis: it moves focus to the
           // address field rather than opening a dialog, exactly as Find does below.
           //
           // Disabled rather than hidden, and not by choice: `if focusAddressField != nil` around
           // this item does compile, but the item then never appears at all. SwiftUI re-evaluates a
           // command's *enabled* state when a `@FocusedValue` changes, but not the menu's structure
           // — so the item is built once while the value is still nil and is never added back.
           // Disabled is the HIG-preferred behaviour anyway, so this costs nothing but the looks.
           Divider()
           Button("Open Location") {
               focusAddressField?()
           }
           .keyboardShortcut("l", modifiers: .command)
           .disabled(focusAddressField == nil || sheetTracker.isAnySheetShown)
           #endif
           Divider()
           Button(selectionTracker.selectedRecipeCount <= 1 ? "Open Recipe in New Window" : "Open Recipes in New Windows") {
               NotificationCenter.default.post(name: .openSelectedRecipesInNewWindows, object: nil)
           }
           .disabled(!selectionTracker.hasRecipeSelected || sheetTracker.isAnySheetShown)
           .keyboardShortcut(.return)
           // Opens any list in its own window without going near the sidebar — the point being to
           // read a recipe and work on its shopping list side by side, which selecting Shopping Lists
           // in the sidebar can't do (it replaces the recipe list). Named rather than acting on a
           // selection for the same reason: the frontmost window is usually showing a recipe.
           // Left out entirely where a second window is impossible (iPhone).
           if MultiWindowSupport.isSupported {
               Menu("Open Shopping List in New Window") {
                   ForEach(shoppingListsMenu.shoppingLists) { list in
                       Button(list.name) {
                           openWindow(id: "shopping-list-window", value: list.id)
                       }
                   }
               }
               .disabled(shoppingListsMenu.shoppingLists.isEmpty)
           }
           // Mirrors the recipe context menu, item for item — same titles, same order, same section
           // heading showing the current value. The menu bar carries it because a contextual menu
           // shouldn't be the only route to a command; unlike right-clicking a row, this one follows
           // the whole selection. Disabled (not hidden) without one, per HIG.
           Menu("Last Prepared Date") {
               Section(selectionTracker.lastPreparedSummary) {
                   Button("Set to Today") {
                       NotificationCenter.default.post(name: .markSelectedRecipesMadeToday, object: nil)
                   }
                   Button("Set as Date…") {
                       NotificationCenter.default.post(name: .setSelectedRecipesLastMadeDate, object: nil)
                   }
                   Divider()
                   Button("Clear") {
                       NotificationCenter.default.post(name: .clearSelectedRecipesLastMade, object: nil)
                   }
               }
           }
           .disabled(!selectionTracker.hasRecipeSelected || sheetTracker.isAnySheetShown)
           Button("Get Info") {
               NotificationCenter.default.post(name: .showRecipeInfoInspector, object: nil)
           }
           .disabled(!selectionTracker.hasRecipeSelected || sheetTracker.isAnySheetShown)
           .keyboardShortcut("i", modifiers: [.command])
           Divider()
           Button("Import from File…") {
               NotificationCenter.default.post(name: .showImportFromFileSheet, object: nil)
           }
           .disabled(sheetTracker.isAnySheetShown)
           Menu("Export…") {
               recipeExportFormatItems(
                   recipeFile: { NotificationCenter.default.post(name: .exportSelectedRecipes, object: nil) },
                   html: { NotificationCenter.default.post(name: .exportSelectedRecipesAsHTML, object: nil) },
                   jsonLD: { NotificationCenter.default.post(name: .exportSelectedRecipesAsJSONLD, object: nil) }
               )
           }
           .disabled(sheetTracker.isAnySheetShown)
           Button("Print…") {
               NotificationCenter.default.post(name: .printSelectedRecipes, object: nil)
           }
           .disabled(!selectionTracker.hasRecipeSelected || sheetTracker.isAnySheetShown)
           #if os(macOS)
           .keyboardShortcut("p", modifiers: [.command])
           #endif
           #if os(macOS)
           Divider()
           Menu("Library") {
               Button("Show Duplicate Recipes…") {
                   #if os(macOS)
                   openWindow(id: "duplicate-recipes-window")
                   #else
                   NotificationCenter.default.post(name: .showDuplicateRecipes, object: nil)
                   #endif
               }
               #if !os(macOS)
               .disabled(sheetTracker.isAnySheetShown)
               #endif
               Button("Consolidate Duplicate Categories, Courses, and Tags…") {
                   #if os(macOS)
                   openWindow(id: "consolidate-duplicates-window")
                   #else
                   NotificationCenter.default.post(name: .showConsolidateDuplicates, object: nil)
                   #endif
               }
               #if !os(macOS)
               .disabled(sheetTracker.isAnySheetShown)
               #endif
           }
           #endif
           Divider()
           // Lands in the macOS and iPadOS menu bars alike (and ⇧⌘R works from a hardware keyboard
           // anywhere). Unlike Settings' Sync Now this respects the recently-synced guard, so
           // mashing the shortcut can't hammer the server.
           Button("Sync Now") {
               Task { await ManualSyncRunner.shared.sync() }
           }
           .keyboardShortcut("r", modifiers: [.command, .shift])
           .disabled(!serverUse || syncService.isSyncing)
           Divider()
       }
       // ⌘F, where the Edit menu's Find items belong. No ellipsis: it moves focus to the search
       // field rather than opening a dialog. Disabled without a recipe list to search — which also
       // hands ⌘F back to the standard Find bar in windows that are only text editing.
       CommandGroup(before: .textEditing) {
           Button("Find") {
               focusSearchField?()
           }
           .keyboardShortcut("f", modifiers: .command)
           .disabled(focusSearchField == nil || sheetTracker.isAnySheetShown)
       }
        CommandGroup(before: .sidebar) {
            // Disabled (not hidden) when no recipe is on screen, per HIG. On macOS this opens a
            // Chef View window; on iPadOS, a full-screen cover — hence the sheet guard.
            Button("Chef View") {
                openChefView?()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(openChefView == nil || sheetTracker.isAnySheetShown)
            Divider()
            Menu("Sort By") {
                Picker("Sort Options", selection: $recipeListSortOrder) {
                    ForEach(RecipeListSortOrderSetting.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                Picker("Sort Direction", selection: $recipeListSortDirection) {
                    ForEach(RecipeListSortDirection.allCases, id: \.self) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.inline)
            }
            Menu("Search Options") {
                Section("Search In…") {
                    ForEach(RecipeListSearchOptions.allCases, id: \.self) { option in
                        Toggle(option.displayName, isOn: binding(for: option))
                    }
                }
            }
            #if os(macOS)
            Divider()
            #endif
            Menu("Sidebar Items") {
                Toggle("Show Favorites", isOn: $showFavorites)
                Toggle("Show Want to Make", isOn: $showWantToMake)
                Divider()
                // Listed in the sidebar's own order; reordering itself lives in General settings.
                ForEach(SidebarSectionOrder.decode(sidebarSectionOrderRaw)) { section in
                    SidebarSectionVisibilityToggle(section: section)
                }
            }
            //Divider()
        }
       // The classifier editors are single-instance `Window` scenes (SaltyApp.swift), and a Window
       // scene adds its own item to the Window menu -- hand-rolled copies here would double them up.
  }
}
