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

struct Menus: Commands {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var sheetTracker = SheetStateTracker()
    @StateObject private var selectionTracker = SelectionStateTracker()
    @AppStorage("recipeListSortOrder") private var recipeListSortOrder: RecipeListSortOrderSetting = .byName
    
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
// TODO: Placeholder for when implement:
//       CommandGroup(before: .sidebar) {
//           Menu("Sort By") {
//               Picker("Sort Options", selection: $recipeListSortOrder) {
//                   ForEach(RecipeListSortOrderSetting.allCases, id: \.self) { option in
//                       Text(option.displayName).tag(option)
//                   }
//               }
//               .pickerStyle(.inline)
//           }
//           Divider()
//       }
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
