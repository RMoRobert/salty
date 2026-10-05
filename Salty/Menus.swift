//
//  Menus.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import SwiftUI
import SaltyCore

struct Menus: Commands {
    @Environment(\.openWindow) private var openWindow
    /// Sort order and search fields, shared with every main window's view model; see `RecipeListSettings`.
    @State private var listSettings = RecipeListSettings.shared
    @State private var syncService = SaltySyncService.shared
    /// The lists behind File ▸ Open Shopping List in New Window. Commands can't reach a scene's view
    /// model, so the menu does its own (tiny) fetch; see `ShoppingListsMenuModel`.
    @State private var shoppingListsMenu = ShoppingListsMenuModel()
    /// Non-nil only while a main window is frontmost; see `MainWindowCommands`. Every command that
    /// acts on a window goes through this, so it reaches that window and no other -- these used to be
    /// `NotificationCenter` broadcasts that every open main window answered at once.
    @FocusedValue(\.mainWindowCommands) private var mainWindow
    /// Non-nil only while the frontmost window is showing a recipe list; carries the selection.
    @FocusedValue(\.recipeSelectionCommands) private var selection
    /// Non-nil only while a window showing the recipe list is frontmost; see `SearchFieldFocusAction`.
    @FocusedValue(\.searchFieldFocusAction) private var focusSearchField
    /// Non-nil only while a window showing a recipe is frontmost; see `ChefViewOpenAction`.
    @FocusedValue(\.chefViewOpenAction) private var openChefView
    /// Non-nil only while the web importer is frontmost; see `AddressFieldFocusAction`.
    @FocusedValue(\.addressFieldFocusAction) private var focusAddressField
    @AppStorage("serverUse") private var serverUse = false

    // Sidebar Items menu: the two fixed Library rows, plus the order the reorderable sections are listed in.
    @AppStorage("sidebarShowFavorites") private var showFavorites = true
    @AppStorage("sidebarShowWantToMake") private var showWantToMake = true
    @AppStorage(SidebarSectionOrder.storageKey) private var sidebarSectionOrderRaw = ""

    /// Only one sheet can be up at a time, so commands that would open another are disabled while the
    /// frontmost window has one (the root's sheets, or the list's own date picker).
    private var isAnySheetShown: Bool {
        mainWindow?.isAnySheetShown == true || selection?.isSheetShown == true
    }

    private var hasRecipeSelected: Bool {
        selection?.hasSelection == true
    }

    /// A search field's toggle; the settings refuse to turn off the last one.
    private func binding(for option: RecipeListSearchOptions) -> Binding<Bool> {
        Binding(
            get: { listSettings.isSearching(option) },
            set: { listSettings.setSearching(option, $0) }
        )
    }

    var body: some Commands {
       ToolbarCommands()
       SidebarCommands()
       // Replaces the stock "New Window" item so ⌘N can belong to New Recipe;
       // New Window is re-added below on ⇧⌘N.
       CommandGroup(replacing: .newItem) {
           Button("New Recipe") {
               mainWindow?.newRecipe()
           }
           .disabled(mainWindow == nil || isAnySheetShown)
           .keyboardShortcut("n", modifiers: [.command])
           Button("New Recipe from Web…") {
               #if os(iOS)
               mainWindow?.createFromWeb()
               #else
               openWindow(id: "create-recipe-from-web-window")
               #endif
           }
           #if os(iOS)
           .disabled(mainWindow == nil || isAnySheetShown)
           #else
           .disabled(isAnySheetShown)
           #endif
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
           .disabled(focusAddressField == nil || isAnySheetShown)
           #endif
           Divider()
           Button((selection?.selectedRecipeCount ?? 0) <= 1 ? "Open Recipe in New Window" : "Open Recipes in New Windows") {
               selection?.openInNewWindows?()
           }
           .disabled(selection?.openInNewWindows == nil || !hasRecipeSelected || isAnySheetShown)
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
               Section(selection?.lastPreparedSummary ?? "Last Prepared") {
                   Button("Set to Today") {
                       selection?.markMadeToday()
                   }
                   Button("Set as Date…") {
                       selection?.setLastMadeDate()
                   }
                   Divider()
                   Button("Clear") {
                       selection?.clearLastMade()
                   }
               }
           }
           .disabled(!hasRecipeSelected || isAnySheetShown)
           Button("Get Info") {
               selection?.showInfo()
           }
           .disabled(!hasRecipeSelected || isAnySheetShown)
           .keyboardShortcut("i", modifiers: [.command])
           Divider()
           Button("Import from File…") {
               mainWindow?.importFromFile()
           }
           .disabled(mainWindow == nil || isAnySheetShown)
           Menu("Export…") {
               recipeExportFormatItems(
                   recipeFile: { mainWindow?.exportRecipeFile() },
                   html: { mainWindow?.exportHTML() },
                   jsonLD: { mainWindow?.exportJSONLD() }
               )
           }
           .disabled(mainWindow == nil || isAnySheetShown)
           Button("Print…") {
               mainWindow?.printSelection()
           }
           .disabled(!hasRecipeSelected || isAnySheetShown)
           #if os(macOS)
           .keyboardShortcut("p", modifiers: [.command])
           #endif
           #if os(macOS)
           Divider()
           // Both are `Window` scenes (SaltyApp.swift); iOS reaches them from the sidebar's Library
           // menu instead, so there is no sheet to open from here.
           Menu("Library") {
               Button("Show Duplicate Recipes…") {
                   openWindow(id: "duplicate-recipes-window")
               }
               Button("Consolidate Duplicate Categories, Courses, and Tags…") {
                   openWindow(id: "consolidate-duplicates-window")
               }
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
           .disabled(focusSearchField == nil || isAnySheetShown)
       }
        CommandGroup(before: .sidebar) {
            // Disabled (not hidden) when no recipe is on screen, per HIG. On macOS this opens a
            // Chef View window; on iPadOS, a full-screen cover — hence the sheet guard.
            Button("Chef View") {
                openChefView?()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(openChefView == nil || isAnySheetShown)
            Divider()
            Menu("Sort By") {
                Picker("Sort Options", selection: $listSettings.sortOrder) {
                    ForEach(RecipeListSortOrderSetting.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                Picker("Sort Direction", selection: $listSettings.sortDirection) {
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
        }
       // The classifier editors are single-instance `Window` scenes (SaltyApp.swift), and a Window
       // scene adds its own item to the Window menu -- hand-rolled copies here would double them up.
  }
}
