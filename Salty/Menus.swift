//
//  Menus.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import SwiftUI

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

    init() {
        NotificationCenter.default.addObserver(
            forName: .recipeSelectionChanged,
            object: nil,
            queue: .main
        ) { notification in
            // Extract the Sendable values before hopping; Notification itself isn't Sendable.
            let hasSelected = notification.userInfo?["hasSelected"] as? Bool
            let count = notification.userInfo?["count"] as? Int
            // Delivered on .main, so assume main-actor isolation to touch this @Observable safely.
            MainActor.assumeIsolated {
                if let hasSelected { self.hasRecipeSelected = hasSelected }
                if let count { self.selectedRecipeCount = count }
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
    
    @AppStorage("recipeListSortOrder") private var recipeListSortOrder: RecipeListSortOrderSetting = .byName
    @AppStorage("recipeListSortDirection") private var recipeListSortDirection: RecipeListSortDirection = .ascending
    
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
       CommandGroup(after: .newItem) {
           Button("Create from Web…") {
               #if os(iOS)
               NotificationCenter.default.post(name: .showCreateFromWebSheet, object: nil)
               #else
               openWindow(id: "create-recipe-from-web-window")
               #endif
           }
           .disabled(sheetTracker.isAnySheetShown)
           Button("Create from Image…") {
               openWindow(id: "create-recipe-from-image-window")
           }
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
           #if os(macOS)
           Divider()
           Button(selectionTracker.selectedRecipeCount <= 1 ? "Open Recipe in New Window" : "Open Recipes in New Windows") {
               NotificationCenter.default.post(name: .openSelectedRecipesInNewWindows, object: nil)
           }
           .disabled(!selectionTracker.hasRecipeSelected || sheetTracker.isAnySheetShown)
           .keyboardShortcut(.return)
           #endif
           Divider()
           Button("Print…") {
               NotificationCenter.default.post(name: .printSelectedRecipes, object: nil)
           }
           .disabled(!selectionTracker.hasRecipeSelected || sheetTracker.isAnySheetShown)
           #if os(macOS)
           .keyboardShortcut("p", modifiers: [.command])
           #endif
           Divider()
           Button("Get Info") {
               NotificationCenter.default.post(name: .showRecipeInfoInspector, object: nil)
           }
           .disabled(!selectionTracker.hasRecipeSelected || sheetTracker.isAnySheetShown)
           .keyboardShortcut("i", modifiers: [.command])
       }
        CommandGroup(before: .sidebar) {
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
                Toggle("Show Categories", isOn: Binding(
                    get: {
                        if UserDefaults.standard.object(forKey: "sidebarShowCategories") == nil {
                            return true // Default to true if not set
                        }
                        return UserDefaults.standard.bool(forKey: "sidebarShowCategories")
                    },
                    set: { UserDefaults.standard.set($0, forKey: "sidebarShowCategories") }
                ))
                Toggle("Show Courses", isOn: Binding(
                    get: {
                        if UserDefaults.standard.object(forKey: "sidebarShowCourses") == nil {
                            return true // Default to true if not set
                        }
                        return UserDefaults.standard.bool(forKey: "sidebarShowCourses")
                    },
                    set: { UserDefaults.standard.set($0, forKey: "sidebarShowCourses") }
                ))
                Toggle("Show Tags", isOn: Binding(
                    get: {
                        if UserDefaults.standard.object(forKey: "sidebarShowTags") == nil {
                            return true // Default to true if not set
                        }
                        return UserDefaults.standard.bool(forKey: "sidebarShowTags")
                    },
                    set: { UserDefaults.standard.set($0, forKey: "sidebarShowTags") }
                ))
            }
            //Divider()
        }
       #if os(macOS)
       CommandGroup(before: .windowList) {
           Button("Edit Categories") {
               openWindow(id: "edit-categories-window")
           }
           Button("Edit Tags") {
               openWindow(id: "edit-tags-window")
           }
           Button("Edit Courses") {
               openWindow(id: "edit-courses-window")
           }
       }
       #endif
  }
}
