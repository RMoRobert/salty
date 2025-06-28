//
//  SaltyApp.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SharingGRDB
import SwiftUI

@main
struct SaltyApp: App {
    @Dependency(\.context) var context
    //let persistenceController = PersistenceController.shared
    init() {
        if context == .live {
            try! prepareDependencies {
                $0.defaultDatabase = try Salty.appDatabase()
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            MainView()
                //.environment(\.managedObjectContext, persistenceController.container.viewContext)

        }
        .commands {
            Menus()
        }
        // "Edit Categories" window
        WindowGroup(id: "edit-categories-window") {
            LibraryCategoriesEditView()
                .frame(idealWidth: 300)
                .navigationTitle("Category Editor")
        }

//        #if !os(macOS)
//        .onChange(of: scenePhase) { _ in
//            persistenceController.save()
//        }
//        #endif
    }
}
