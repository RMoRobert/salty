//
//  Menus.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import SwiftUI

struct Menus: Commands {
   @Environment(\.openWindow) private var openWindow
    
   var body: some Commands {
       ToolbarCommands()
       SidebarCommands()
       CommandGroup(after: .newItem) {
           Button("Open Database…") {
               openWindow(id: "open-database-window")
           }
           Divider()
           Button("Create Recipe from Web…") {
               openWindow(id: "create-recipe-from-web-window")
           }
           Button("Create Recipe from Image…") {
               openWindow(id: "create-recipe-from-image-window")
           }
           Divider()
           Button("Import from File…") {
               openWindow(id: "import-from-file-window")
           }
       }
       #if os(macOS)
       CommandGroup(before: .windowList) {
           Button("Edit Categories") {
               openWindow(id: "edit-categories-window")
           }
       }
       #endif
  }
}
