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
       CommandGroup(before: .printItem) {
           Button("Import…") {
               //openWindow(id: "import-page")
               print("TODO!")
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
