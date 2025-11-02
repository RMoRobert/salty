//
//  Menus.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import SwiftUI

// Want to disable some menu items on macOS (and iPadOS 26+?) when
// sheets are open since can't open more than one; this should help
class SheetStateTracker: ObservableObject {
    @Published var isAnySheetShown = false
    
    init() {
        NotificationCenter.default.addObserver(
            forName: .sheetStateChanged,
            object: nil,
            queue: .main
        ) { notification in
            if let isShown = notification.userInfo?["isShown"] as? Bool {
                self.isAnySheetShown = isShown
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// Track recipe selection state for enabling/disabling menu items
class SelectionStateTracker: ObservableObject {
    @Published var hasRecipeSelected = false
    
    init() {
        NotificationCenter.default.addObserver(
            forName: .recipeSelectionChanged,
            object: nil,
            queue: .main
        ) { notification in
            if let hasSelected = notification.userInfo?["hasSelected"] as? Bool {
                self.hasRecipeSelected = hasSelected
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// Track search options state to make menu reactive to UserDefaults changes
class SearchOptionsTracker: ObservableObject {
    @Published private var optionStates: [RecipeListSearchOptions: Bool] = [:]
    
    init() {
        // Initialize from UserDefaults
        loadFromUserDefaults()
        
        // Observe UserDefaults changes
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadFromUserDefaults()
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
                // Set default: name = true, others = false
                let defaultValue = option == .name
                UserDefaults.standard.set(defaultValue, forKey: option.userDefaultsKey)
                optionStates[option] = defaultValue
            }
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
    }
}

struct Menus: Commands {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var sheetTracker = SheetStateTracker()
    @StateObject private var selectionTracker = SelectionStateTracker()
    @StateObject private var searchOptionsTracker = SearchOptionsTracker()
    
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
           Button("Create Recipe from Web…") {
               #if os(iOS)
               NotificationCenter.default.post(name: .showCreateFromWebSheet, object: nil)
               #else
               openWindow(id: "create-recipe-from-web-window")
               #endif
           }
           .disabled(sheetTracker.isAnySheetShown)
           Button("Create Recipe from Image…") {
               openWindow(id: "create-recipe-from-image-window")
           }
           Divider()
           Button("Import from File…") {
               NotificationCenter.default.post(name: .showImportFromFileSheet, object: nil)
           }
           .disabled(sheetTracker.isAnySheetShown)
           Button("Export to File…") {
               NotificationCenter.default.post(name: .exportSelectedRecipes, object: nil)
           }
           .disabled(sheetTracker.isAnySheetShown)
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
