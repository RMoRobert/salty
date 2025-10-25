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

struct Menus: Commands {
   @Environment(\.openWindow) private var openWindow
   @StateObject private var sheetTracker = SheetStateTracker()
    
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
       }
//       CommandGroup(before: .sidebar) {
//           Menu("Sort By") {
//               Button("Name") {
//                   // TODO: Implement name sorting
//               }
//               Button("Date Modified") {
//                   // TODO: Implement date modified sorting
//               }
//               Button("Date Created/Added") {
//                   // TODO: Implement date created sorting
//               }
//               Button("Source") {
//                   // TODO: Implement source sorting
//               }
//               Button("Rating") {
//                   // TODO: Implement rating sorting
//               }
//               Button("Difficulty") {
//                   // TODO: Implement difficulty sorting
//               }
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
