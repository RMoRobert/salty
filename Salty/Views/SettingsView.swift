//
//  SettingsView.swift
//  Salty
//
//  Created by Robert on 7/6/25.
//

import SwiftUI
import SQLiteData
import OSLog

struct SettingsView: View {
    @Dependency(\.defaultDatabase) private var database
    @State private var diagnosticsInfo: [String: Any] = [:]
    
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Theme", systemImage: "paintbrush") {
                ThemeSettingsView()
            }
            Tab("Database", systemImage: "externaldrive") {
                DatabaseSettingsView(diagnosticsInfo: $diagnosticsInfo)
            }
            Tab("Server", systemImage: "globe") {
                ServerSettingsView()
            }
            Tab("Advanced", systemImage: "gearshape.2") {
                AdvancedSettingsView()
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 500, height: 600)
        #endif
        .onAppear {
            diagnosticsInfo = FileManager.getDatabaseAccessDiagnostics()
        }
    }
}

enum RecipeListViewStyle: String, Codable {
    case summary, smallIcons
}

struct DatabaseSettingsView: View {
    private let logger = Logger(subsystem: "Salty", category: "Settings")
    @Binding var diagnosticsInfo: [String: Any]
    @State private var showingResetConfirmation = false
    @State private var showingOpenDatabaseSheet = false
    @State private var isDiagnosticsExpanded = false

    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(FileManager.customSaltyLibraryDirectory == nil ? "Current Location (Default):" : "Current Location (Custom):")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(FileManager.customSaltyLibraryDirectory?.path ?? FileManager.defaultDatabaseFileFullPath.path)
                        .font(.caption)
                        .textSelection(.enabled)
                    Button("Select Custom Database Location…") {
                            showingOpenDatabaseSheet = true
                        }
                        
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button("Reset to Default Location", role: .destructive) {
                    showingResetConfirmation = true
                }
                #if os(macOS)
                .buttonStyle(.link)
                #else
                .controlSize(.small)
                #endif
            } header: {
                Text("Database Location")
            }
            
            Section {
                DisclosureGroup(isExpanded: $isDiagnosticsExpanded) {
                    Text(FileManager.getDatabaseTroubleshootingGuidance())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                    
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(diagnosticsInfo.keys.sorted(), id: \.self) { key in
                            DiagnosticRow(key: key, value: diagnosticsInfo[key])
                        }
                    }
                    
                    HStack {
                        Button("Refresh") {
                            diagnosticsInfo = FileManager.getDatabaseAccessDiagnostics()
                        }
                    }
                } label: {
                    Text("Show Diagnostics")
                }
            } header: {
                Text("Database Diagnostics")
            }
        }
        .alert("Reset Database Location", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefaultDatabaseLocation()
            }
        } message: {
            Text("This will reset your database location to the default location. You'll need to restart the app for changes to take effect.")
        }
        .sheet(isPresented: $showingOpenDatabaseSheet) {
            OpenDBView()
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
        }
    }
    
    private func resetToDefaultDatabaseLocation() {
        FileManager.clearCustomLocationBookmarks()
        logger.debug("Reset database location to default")
        // Refresh diagnostics after reset
        diagnosticsInfo = FileManager.getDatabaseAccessDiagnostics()
    }
}

struct ServerSettingsView: View {
    @AppStorage("serverUse") private var serverUse = false
    @AppStorage("serverUrl") private var serverUrl: String = ""
    @AppStorage("savePasswordInKeychain") private var savePasswordInKeychain = false
    @AppStorage("autoSyncEnabled") private var autoSyncEnabled = false
    @State private var syncService = SaltySyncService.shared
    @State private var autoSync = AutoSyncCoordinator.shared
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""
    @State private var syncAlertIsError = false
    @State private var password: String = ""
    @State private var hasLoadedPassword = false
    @State private var showingForceResyncConfirm = false
    @State private var showingSaltyServerHelpAlert = false
    
    var body: some View {
        Form {
            Section {
                let serverToggle =
                Toggle("Enable sync with Salty Server", isOn: $serverUse)
                    .onChange(of: serverUse) { oldValue, newValue in
                        if newValue && !hasLoadedPassword {
                            loadPasswordIfEnabled()
                        } else if !newValue {
                            // Clear password from memory when sync is disabled
                            password = ""
                        }
                    }
                let helpButton = Button("What's this?", systemImage:  "questionmark.circle") {
                    showingSaltyServerHelpAlert = true
                }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                HStack {
#if os(macOS)
                    serverToggle
                        .padding(.leading, 1)
                    helpButton
#else
                    helpButton
                    serverToggle
#endif
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Server URL", text: $serverUrl)
                        .disabled(!serverUse)
                        .textContentType(.URL)
#if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
#endif
                    if (!serverUrl.isEmpty && !serverUrl.lowercased().starts(with: "https")) {
                        Text("WARNING: It is recommended to use HTTPS for better security.")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(verbatim: "Example: https://server.example.com:8443")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                TextField("Username", text: $syncService.serverUsername)
                    .disabled(!serverUse)
                
                SecureField("Password", text: $password)
                    .disabled(!serverUse)
                    .onChange(of: password) { oldValue, newValue in
                        // Only save to Keychain if sync is enabled and user wants to save it
                        if serverUse && savePasswordInKeychain {
                            syncService.serverPassword = newValue
                        }
                    }                
                if serverUse {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Save password securely in Keychain", isOn: $savePasswordInKeychain)
                            .onChange(of: savePasswordInKeychain) { oldValue, newValue in
                                if newValue && !password.isEmpty {
                                    // Save current password to Keychain
                                    syncService.serverPassword = password
                                } else if !newValue {
                                    // Remove from Keychain (but keep in memory for current session)
                                    syncService.serverPassword = ""
                                }
                            }
                        Text("If not saved, you will need to enter your password on every sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } header: {
                Text("Server Configuration")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Sync automatically", isOn: $autoSyncEnabled)
                        .disabled(!serverUse)
                    Text("Syncs in the background after you make changes, on launch, and when returning to the app. Requires saving your password in the Keychain. Occasional failures are silent; persistent ones show a dismissable banner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        // Always use the current UI credentials for sync (token for background tasks only -- not yet implemented)
                        // Clear any existing token to force re-authentication with current UI values
                        syncService.logout()
                        // Set password in sync service (will be used for authentication)
                        syncService.serverPassword = password
                        await performSync()
                        // Clear password from sync service if not saving to Keychain
                        if !savePasswordInKeychain {
                            syncService.serverPassword = ""
                        }
                    }
                } label: {
                    HStack {
                        if syncService.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Syncing...")
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Now")
                        }
                    }
                }
                .disabled(!serverUse || serverUrl.isEmpty || syncService.isSyncing || password.isEmpty || syncService.serverUsername.isEmpty)
                
                Button {
                    syncService.logout()
                    syncAlertIsError = false
                    syncAlertMessage = "Login token cleared. Next sync will re-authenticate with the current credentials."
                    showingSyncAlert = true
                } label: {
                        Text("Clear Saved Token")
                }
                #if os(macOS)
                .buttonStyle(.link)
                #endif
                .controlSize(.small)
                .disabled(syncService.isSyncing)

                Button(role: .destructive) {
                    showingForceResyncConfirm = true
                } label: {
                    Text("Force Full Re-Sync")
                }
                #if os(macOS)
                .buttonStyle(.link)
                #endif
                .controlSize(.small)
                .disabled(!serverUse || serverUrl.isEmpty || syncService.isSyncing || password.isEmpty || syncService.serverUsername.isEmpty)

                if syncService.isSyncing {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(syncService.syncProgress.currentStep)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(syncService.syncProgress.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let lastSync = syncService.lastSyncDate {
                    HStack {
                        Text("Last synced:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(lastSync, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let error = syncService.lastSyncError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if autoSync.isPaused, let until = autoSync.pausedUntil {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.secondary)
                        Text("Automatic sync paused until \(until.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Resume") { autoSync.resume() }
                            .controlSize(.small)
                    }
                }

//                #if DEBUG
//                Button("Show Test Failure Banner") {
//                    AutoSyncCoordinator.shared.showFailureBanner = true
//                }
//                .controlSize(.small)
//                #endif
            } header: {
                Text("Sync")
            }
            
            Section {
                Text("Compares your local recipes with the server and syncs changes in both directions. The most recently modified version wins in case of conflicts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("How Sync Works")
            }
        }
        .alert(syncAlertIsError ? "Sync Failed" : "Sync Complete", isPresented: $showingSyncAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncAlertMessage)
        }
        .confirmationDialog("Force Full Re-Sync?", isPresented: $showingForceResyncConfirm, titleVisibility: .visible) {
            Button("Delete Local, Pull from Server", role: .destructive) {
                Task {
                    syncService.logout()
                    syncService.serverPassword = password
                    await performForceResync()
                    if !savePasswordInKeychain {
                        syncService.serverPassword = ""
                    }
                }
            }
            Button("Delete Server, Push from Local", role: .destructive) {
                Task {
                    syncService.logout()
                    syncService.serverPassword = password
                    await performForcePush()
                    if !savePasswordInKeychain {
                        syncService.serverPassword = ""
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A full re-sync will delete all content from either the local device or the server and force a re-sync from the other direction. We suggest making a database backup before using this option. Please select a force-sync method.")
        }
        .onAppear {
            if serverUse && !hasLoadedPassword {
                loadPasswordIfEnabled()
            }
        }
        .alert("What is Salty Server?", isPresented: $showingSaltyServerHelpAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Salty Server is an optional, self-hosted sync service you can add to sync your database among multiple devices (as an alternative to moving or copying the database file yourself or relying on third-party services). For details, see: https://github.com/rmorobert/saltyserver")
        }
    }
    
    private func loadPasswordIfEnabled() {
        // Only load from Keychain if sync is enabled and user wants to save password
        if serverUse && savePasswordInKeychain {
            password = syncService.serverPassword
            hasLoadedPassword = true
        } else {
            // Don't load from Keychain - user will enter password manually
            password = ""
            hasLoadedPassword = true
        }
    }
    
    private func performSync() async {
        do {
            try await syncService.syncNow()
            syncAlertIsError = false
            syncAlertMessage = "Successfully synced with server.\n\(syncService.syncProgress.summary)"
            showingSyncAlert = true
        } catch {
            syncAlertIsError = true
            syncAlertMessage = friendlySyncMessage(error)
            showingSyncAlert = true
        }
    }

    private func performForceResync() async {
        do {
            try await syncService.forceFullResyncFromServer()
            syncAlertIsError = false
            syncAlertMessage = "Full re-sync complete.\n\(syncService.syncProgress.summary)"
            showingSyncAlert = true
        } catch {
            syncAlertIsError = true
            syncAlertMessage = friendlySyncMessage(error)
            showingSyncAlert = true
        }
    }

    private func performForcePush() async {
        do {
            try await syncService.forceFullResyncToServer()
            syncAlertIsError = false
            syncAlertMessage = "Full re-sync complete.\n\(syncService.syncProgress.summary)"
            showingSyncAlert = true
        } catch {
            syncAlertIsError = true
            syncAlertMessage = friendlySyncMessage(error)
            showingSyncAlert = true
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("mobileEditViews") private var useMobileEditViews = false
    @AppStorage("listViewStyle") private var listViewStyle: RecipeListViewStyle = .summary
    @AppStorage("sidebarShowFavorites") private var showFavorites = true
    @AppStorage("sidebarShowWantToMake") private var showWantToMake = true
    @AppStorage("sidebarShowCategories") private var showCategories = true
    @AppStorage("sidebarShowCourses") private var showCourses = true
    @AppStorage("sidebarShowTags") private var showTags = true
    
    // Computed properties for bindings that ensure at least one is always checked
    private var showCategoriesBinding: Binding<Bool> {
        Binding(
            get: { showCategories },
            set: { newValue in
                // Only allow unchecking if at least one other item is checked
                if !newValue {
                    let othersChecked = showCourses || showTags
                    if othersChecked {
                        showCategories = false
                    }
                } else {
                    showCategories = true
                }
            }
        )
    }
    
    private var showCoursesBinding: Binding<Bool> {
        Binding(
            get: { showCourses },
            set: { newValue in
                // Only allow unchecking if at least one other item is checked
                if !newValue {
                    let othersChecked = showCategories || showTags
                    if othersChecked {
                        showCourses = false
                    }
                } else {
                    showCourses = true
                }
            }
        )
    }
    
    private var showTagsBinding: Binding<Bool> {
        Binding(
            get: { showTags },
            set: { newValue in
                // Only allow unchecking if at least one other item is checked
                if !newValue {
                    let othersChecked = showCategories || showCourses
                    if othersChecked {
                        showTags = false
                    }
                } else {
                    showTags = true
                }
            }
        )
    }
    
    var body: some View {
        Form {
            Section {
                Picker(selection: $listViewStyle) {
                    Text("Summary (Default)").tag(RecipeListViewStyle.summary)
                    Text("Small Icons").tag(RecipeListViewStyle.smallIcons)
                } label: {
                    Text("Style")
                        .accessibilityLabel("Recipe List View Style")
                }
            } header: {
                Text("Recipe List View Style")
            }
            Section {
                Toggle("Show Favorites", isOn: $showFavorites)
                Toggle("Show Want to Make", isOn: $showWantToMake)
                Toggle("Show Categories", isOn: showCategoriesBinding)
                Toggle("Show Courses", isOn: showCoursesBinding)
                Toggle("Show Tags", isOn: showTagsBinding)
            } header: {
                Text("Sidebar Items")
                    #if os(macOS)
                    .padding(.top)
                    #endif
            } footer: {
                Text("At least one of Categories, Courses, or Tags must be enabled.")
                    .font(.caption)
            }
        }
    }
}

struct ThemeSettingsView: View {
    @AppStorage("webPreviews") private var useWebRecipeDetailView = false
    @AppStorage("recipeHtmlTheme") private var recipeHtmlTheme: RecipeHtmlTheme = .modern
    @AppStorage("monospacedBulkEditFont") private var monospacedBulkEditFont = false

    var body: some View {
        Form {
            Section {
                Toggle("Use web-based recipe detail view (instead of native UI-based view; experimental)", isOn: $useWebRecipeDetailView)
                    .fixedSize(horizontal: false, vertical: true)
                if useWebRecipeDetailView {
                    Picker("Theme", selection: $recipeHtmlTheme) {
                        ForEach(RecipeHtmlTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                }
            } header: {
                Text("Recipe Display")
                    #if os(macOS)
                    .padding(.top)
                    #endif
            }
            Section {
                Toggle("Use monospaced font in bulk recipe ingredient and direction edit forms", isOn: $monospacedBulkEditFont)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Editing")
                    #if os(macOS)
                    .padding(.top)
                    #endif
            }
        }
    }
}

struct AdvancedSettingsView: View {
    @State private var backupManager = DatabaseBackupManager()
    @State private var isCreatingBackup = false
    @State private var backupMessage = ""
    @State private var showingDeleteConfirmation = false
    @State private var isRegeneratingThumbnails = false
    @State private var thumbnailMessage = ""
    
    var body: some View {
        Form {
            Section {
                Text("Salty automatically creates and stores up to a three recent backups of your recipe library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                
                HStack {
                    Button(isCreatingBackup ? "Creating..." : "Create Backup Now") {
                        createBackupNow()
                    }
                    .disabled(isCreatingBackup)
                    
                    Button("Delete All Backups", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
                #if os(macOS)
                Button("Open Backup Folder") {
                    NSWorkspace.shared.open(backupManager.getBackupDirectory())
                }
                .controlSize(.small)
                #endif
                if !backupMessage.isEmpty {
                    Text(backupMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Database Backups")
            }
            
            Section {
                // Group the button + caption into ONE Form row (a VStack) so no separator is drawn
                // between them — matches the "control with description beneath" cells in System Settings.
                VStack(alignment: .leading, spacing: 6) {
                    Button("Clean Up Orphaned Images") {
                        Task {
                            await RecipeImageManager.shared.cleanupOrphanedImages()
                        }
                    }
                    .buttonStyle(.bordered)
                    Text("This will remove all images stored alongside your recipe library database that are not referenced in the database. It should be safe, but we suggest having a backup before running (as you should periodically regardless).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button(isRegeneratingThumbnails ? "Regenerating…" : "Regenerate Preview Thumbnails") {
                        regenerateThumbnails()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRegeneratingThumbnails)
                    Text("Rebuilds the small preview images shown in the recipe list from your full-size photos. Useful if older previews look stretched or squashed. Your photos are not modified.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !thumbnailMessage.isEmpty {
                        Text(thumbnailMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Image Cleanup")
            }
        }
        .alert("Delete All Backups", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllBackups()
            }
        } message: {
            Text("This will permanently delete all database backup files. This action cannot be undone.")
        }
    }
    
    private func regenerateThumbnails() {
        isRegeneratingThumbnails = true
        thumbnailMessage = ""

        Task {
            let result = await RecipeImageManager.shared.regenerateAllThumbnails()
            isRegeneratingThumbnails = false
            if result.updated == 0 && result.failed == 0 {
                thumbnailMessage = "No recipe images found to regenerate."
            } else {
                var message = "Regenerated \(result.updated) preview\(result.updated == 1 ? "" : "s")."
                if result.failed > 0 {
                    message += " \(result.failed) could not be read and were skipped."
                }
                thumbnailMessage = message
            }
        }
    }

    private func createBackupNow() {
        isCreatingBackup = true
        backupMessage = "Creating backup..."
        
        backupManager.createBackupNow()
        
        // Wait a moment and then update the message
        Task {
            try? await Task.sleep(for: .seconds(2))
            isCreatingBackup = false
            backupMessage = "Backup created successfully!"

            // Clear the message after a couple seconds
            Task {
                try? await Task.sleep(for: .seconds(2))
                backupMessage = ""
            }
        }
    }
    
    private func deleteAllBackups() {
        do {
            let backupFiles = backupManager.getAvailableBackups()
            for backupURL in backupFiles {
                try FileManager.default.removeItem(at: backupURL)
            }
            backupMessage = "All backups deleted successfully"
            
            // Clear the message after a couple seconds
            Task {
                try? await Task.sleep(for: .seconds(2))
                backupMessage = ""
            }
        } catch {
            backupMessage = "Error deleting backups: \(error.localizedDescription)"
        }
    }
}

struct DiagnosticRow: View {
    let key: String
    let value: Any?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            
            Text(String(describing: value ?? "nil"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .clipShape(.rect(cornerRadius: 4))
        }
        .padding(.vertical, 2)
    }
}


#Preview {
    SettingsView()
}
