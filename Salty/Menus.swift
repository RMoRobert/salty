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
           Button("Import from Web…") {
               openWindow(id: "import-from-web-window")
           }
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
