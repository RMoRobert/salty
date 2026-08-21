//
//  SaltyApp.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import OSLog
import SQLiteData
import SwiftUI
import SaltyCore
#if os(macOS)
import AppKit
#endif

@main
struct SaltyApp: App {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    /// Chef View cooking progress, shared by every scene that can show a recipe — leave Chef View,
    /// glance at something else, come back to the same current step. In-memory only; see
    /// ChefSessionState. The shared instance (not a fresh one) so the iOS external-display scene,
    /// which lives outside this environment, observes the same progress.
    @State private var chefSessionStore = ChefViewSessionStore.shared

    // No app delegate: the external-display (AirPlay / HDMI) scene — the one scene role SwiftUI
    // can't declare — is claimed declaratively by the UIApplicationSceneManifest in Info.plist,
    // which names ExternalDisplaySceneDelegate for it. Verified: with the manifest present, UIKit
    // never consults a delegate's configurationForConnecting for that role, so an adaptor here
    // would be dead code.

    /// The live database writer, kept so we can checkpoint its WAL when the app quiesces (so SaltyKMP,
    /// syncing the linked folder, sees the latest data in the main `.sqlite`). Nil in non-live contexts.
    private let database: (any DatabaseWriter)?

    init() {
        // Locals (not stored properties): init must not touch `self` until `database` is assigned below.
        let logger = Logger(subsystem: "Salty", category: "App")
        @Dependency(\.context) var context

        var createdDatabase: (any DatabaseWriter)? = nil
        if context == .live {
#if os(macOS)
            // One-shot, and the last time the login-keychain authorization dialog can appear: everything
            // afterwards uses the data-protection keychain. See migrateLegacyMacKeychainIfNeeded().
            KeychainHelper.shared.migrateLegacyMacKeychainIfNeeded()
#endif
            do {
                // Begin (and hold) security-scoped access to the database location before opening it.
                FileManager.beginAccessingDatabaseLocation()

                // Validate access; if a custom location can't be reached, try one fresh resolution.
                if !FileManager.validateDatabaseAccess() {
                    logger.error("Warning: Database access validation failed. Attempting to re-resolve location bookmark...")
                    if FileManager.refreshCustomDatabaseBookmark() {
                        logger.debug("Successfully re-resolved database location bookmark")
                    } else {
                        logger.error("Failed to re-resolve database location - may need user intervention")
                    }
                }

                let db = try Salty.appDatabase()
                createdDatabase = db
                prepareDependencies {
                    $0.defaultDatabase = db
                }

#if os(macOS)
                // Cmd-Q doesn't reliably drive scenePhase → checkpoint on terminate so the handoff file is current.
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification, object: nil, queue: .main
                ) { [db] _ in
                    checkpointDatabaseForHandoff(db)
                }
#endif

                // Create backup after successful database initialization
                let backupManager = DatabaseBackupManager()
                backupManager.createBackupIfNeeded()
            } catch {
                // Log the error but don't crash the app
                logger.error("Failed to initialize database: \(error)")
            }
        }
        self.database = createdDatabase
    }
    
    var body: some Scene {
        // Main window; the id lets File ▸ New Window open another one (see Menus.swift)
        WindowGroup(id: "main-window") {
            MainView()
                .handlesExternalEvents(preferring: ["salty-recipe"], allowing: ["*"])
                .environment(chefSessionStore)
        }
        .handlesExternalEvents(matching: ["salty-recipe"])
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // iOS: fires on background. (macOS quit handled by the willTerminate observer in init.)
                if let database { checkpointDatabaseForHandoff(database) }
                AutoSyncCoordinator.shared.appWillBackground()
            case .active:
                // Launch / return-to-foreground: pull server-side changes if auto-sync is on (throttled).
                Task { await AutoSyncCoordinator.shared.appBecameActive() }
            default:
                break
            }
        }
        .commands {
            Menus()
        }
        
        // The three classifier editors (File ▸ Library; sheets on iOS). `Window` rather than
        // `WindowGroup`: each is a single-instance editor of one library table, so a second copy of
        // the same one is only ever a way to get two lists fighting over the same rows.
        // (macOS only: iOS presents them as sheets from the sidebar's Library menu, and the commands
        // that open these are themselves macOS-only -- see Menus.swift.)
        #if os(macOS)
        classifierEditorWindow(.category, id: "edit-categories-window")
        classifierEditorWindow(.tag, id: "edit-tags-window")
        classifierEditorWindow(.course, id: "edit-courses-window")
        #endif
        // "Show Duplicate Recipes" window (File ▸ Library; a sheet on iOS)
        WindowGroup(id: "duplicate-recipes-window") {
            NavigationStack {
                DuplicateRecipesView()
            }
            .frame(minWidth: 420, idealWidth: 640, minHeight: 400, idealHeight: 600)
        }
        // "Consolidate Duplicate Categories, Courses, and Tags" window (File ▸ Library; a sheet on iOS)
        WindowGroup(id: "consolidate-duplicates-window") {
            NavigationStack {
                ConsolidateDuplicatesView()
            }
            .frame(minWidth: 420, idealWidth: 620, minHeight: 360, idealHeight: 520)
        }
        // "Open Database" window
        WindowGroup(id: "open-database-window") {
            OpenDBView()
                #if os(macOS)
                .frame(minWidth: 300, minHeight: 400)
                #endif
                .navigationTitle("Open Database")
        }

        // "Import from Web" window
        WindowGroup(id: "create-recipe-from-web-window") {
            CreateRecipeFromWebView()
                .frame(idealWidth: 1200)
                .navigationTitle("Import Recipe from Web")
        }
        #if os(macOS)
        // Wide enough that the browser pane clears the 500pt compact threshold, below which the
        // address field drops out of the toolbar entirely. At the old 800 the split left each pane
        // around 400, so the window opened collapsed every time.
        .defaultSize(width: 1200, height: 800)
        // Expanded rather than the default unified style: this window's toolbar carries a browser's
        // worth of chrome -- nav buttons, an address field, and the two import actions -- and sharing
        // one row with the traffic lights and the title left it starved for width. Expanded drops
        // the title onto its own line and gives the toolbar the full window width beneath it.
        .windowToolbarStyle(.expanded)
        #endif
        // "Import from Image" window
        WindowGroup(id: "create-recipe-from-image-window") {
            CreateRecipeFromImageView()
                .frame(idealWidth: 800)
                .navigationTitle("Import Recipe from Image")
        }

        // One shopping list in a window of its own, so it can be edited beside a recipe instead of
        // replacing the recipe list in the main window. `for: String.self` — the list id — gives each
        // list its own window, and makes re-opening a list that's already open bring that window
        // forward rather than stacking a duplicate onto the same rows.
        //
        // Not macOS-only: iPad supports multiple scenes as well (Info.plist opts in), which is where
        // Split View and iPadOS 26 windowing pick it up. iPhone can't, and simply never opens it —
        // every command that would is gated on MultiWindowSupport.
        WindowGroup(id: "shopping-list-window", for: String.self) { $listId in
            NavigationStack {
                ShoppingListWindowView(listId: $listId)
            }
            #if os(macOS)
            .frame(minWidth: 300, idealWidth: 420, minHeight: 320, idealHeight: 640)
            #endif
        }
        .defaultSize(width: 420, height: 640)

        #if os(macOS)
        // Standalone recipe viewer (narrow split views → open full detail in its own window)
        WindowGroup(id: "recipe-detail-window", for: String.self) { $recipeId in
            NavigationStack {
                RecipeDetailWindowView(recipeId: $recipeId)
            }
            .frame(minWidth: 520, idealWidth: 720, minHeight: 420, idealHeight: 680)
            .environment(chefSessionStore)
        }
        .defaultSize(width: 720, height: 680)

        // Chef View gets its own window on macOS so it can go full screen on an external display or
        // TV while the main window stays usable. iOS/iPadOS presents it as a full-screen cover from
        // the recipe detail view instead.
        WindowGroup(id: "chef-view-window", for: ChefViewLaunch.self) { $launch in
            ChefViewWindowView(launch: $launch)
                .frame(minWidth: 640, idealWidth: 1100, minHeight: 480, idealHeight: 760)
                .environment(chefSessionStore)
        }
        .defaultSize(width: 1100, height: 760)

        Settings {
            SettingsView()
        }
        #endif
    }

    #if os(macOS)
    /// One classifier editor window. The three differ only in which table they edit, so they share
    /// both the scene shape and the view (see `LibraryClassifiersEditView`).
    private func classifierEditorWindow(_ classifier: LibraryClassifier, id: String) -> some Scene {
        Window("Edit \(classifier.pluralLabel)", id: id) {
            LibraryClassifiersEditView(classifier: classifier)
                .frame(minWidth: 320, idealWidth: 420, minHeight: 320, idealHeight: 520)
        }
    }
    #endif
}

func isLiquidGlassAvailable() -> Bool {
    if #available(iOS 26.0, macOS 26.0, *) {
        return true
    }
    else {
        return false
    }
}
