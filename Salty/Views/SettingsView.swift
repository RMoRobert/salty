//
//  SettingsView.swift
//  Salty
//
//  Created by Robert on 7/6/25.
//

import SwiftUI
import SQLiteData
import OSLog

/// Returns the heading text with a trailing colon on macOS (platform convention) and unchanged on iOS.
private func platformSpecificHeadingName(_ text: String) -> String {
    #if os(macOS)
    return text + ":"
    #else
    return text
    #endif
}

struct SettingsView: View {
    @Dependency(\.defaultDatabase) private var database
    @State private var diagnosticsInfo: [String: Any] = [:]
    
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
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
        .scenePadding()
        .frame(maxWidth: 450, minHeight: 350)
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
                Button("Select Custom Database Location…") {
                    showingOpenDatabaseSheet = true
                }
                #if os(macOS)
                .padding(.bottom, 6)
                #endif
                
                Text(FileManager.customSaltyLibraryDirectory == nil ? "Current Location (Default):" : "Current Location (Custom):")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(FileManager.customSaltyLibraryDirectory?.path ?? FileManager.defaultDatabaseFileFullPath.path)
                    .font(.caption)
                    .padding(6)
                    .textSelection(.enabled)
                
                Button("Reset to Default Location", role: .destructive) {
                    showingResetConfirmation = true
                }
                #if os(macOS)
                .buttonStyle(.link)
                #else
                .controlSize(.small)
                #endif
            } header: {
                Text(platformSpecificHeadingName("Database Location"))
                     #if os(macOS)
                     .font(.headline)
                     .bold()
                     .padding(.top, 8)
                     #endif
            }
            
            Section {
                DisclosureGroup(isExpanded: $isDiagnosticsExpanded) {
                    Text(FileManager.getDatabaseTroubleshootingGuidance())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                    
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(diagnosticsInfo.keys.sorted()), id: \.self) { key in
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
                Text(platformSpecificHeadingName("Database Diagnostics"))
                    #if os(macOS)
                    .font(.headline)
                    .bold()
                    .padding(.top, 8)
                    #endif
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
    @State private var syncService = SaltySyncService.shared
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""
    @State private var syncAlertIsError = false
    @State private var password: String = ""
    @State private var hasLoadedPassword = false
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
                
                TextField(platformSpecificHeadingName("Server URL"), text: $serverUrl)
                    .disabled(!serverUse)
                    .textContentType(.URL)
#if os(iOS)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
#endif
                VStack(alignment: .leading) {
                    if (!serverUrl.isEmpty && !serverUrl.starts(with: "https")) {
                        Text("WARNING: It is recommended to use HTTPS for better security.")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verbatim: "Example: https://sever.example.com:8443")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                TextField(platformSpecificHeadingName("Username"), text: $syncService.serverUsername)
                    .disabled(!serverUse)
                
                SecureField(platformSpecificHeadingName("Password"), text: $password)
                    .disabled(!serverUse)
                    .onChange(of: password) { oldValue, newValue in
                        // Only save to Keychain if sync is enabled and user wants to save it
                        if serverUse && savePasswordInKeychain {
                            syncService.serverPassword = newValue
                        }
                    }                
                if serverUse {
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
                }
            } header: {
                Text(platformSpecificHeadingName("Server Configuration"))
                     #if os(macOS)
                     .font(.headline)
                     .bold()
                     .padding(.top, 6)
                     .padding(.bottom, 4)
                     #endif
            }
            
            Section {
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
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text(platformSpecificHeadingName("Sync"))
                    #if os(macOS)
                    .font(.headline)
                    .bold()
                    .padding(.top, 4)
                    #endif
            }
            
            Section {
                Text("Compares your local recipes with the server and syncs changes in both directions. The most recently modified version wins in case of conflicts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(platformSpecificHeadingName("How Sync Works"))
            }
        }
        .alert(syncAlertIsError ? "Sync Failed" : "Sync Complete", isPresented: $showingSyncAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncAlertMessage)
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
            syncAlertMessage = error.localizedDescription
            showingSyncAlert = true
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("webPreviews") private var useWebRecipeDetailView = false
    @AppStorage("mobileEditViews") private var useMobileEditViews = false
    @AppStorage("monospacedBulkEditFont") private var monospacedBulkEditFont = false
    @AppStorage("listViewStyle") private var listViewStyle: RecipeListViewStyle = .summary
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
                    Text(platformSpecificHeadingName("Style"))
                        .accessibilityLabel("Recipe List View Style")
                }
            } header: {
                Text(platformSpecificHeadingName("Recipe List View Style"))
            }
            Section {
                Toggle("Show Categories", isOn: showCategoriesBinding)
                Toggle("Show Courses", isOn: showCoursesBinding)
                Toggle("Show Tags", isOn: showTagsBinding)
            } header: {
                Text(platformSpecificHeadingName("Sidebar Items"))
                    #if os(macOS)
                    .padding(.top)
                    #endif
            } footer: {
                Text("At least one sidebar item must be enabled.")
                    .font(.caption)
            }
            Section {
                Toggle("Use web-based recipe detail view (instead of native UI-based view; experimental)", isOn: $useWebRecipeDetailView)
                Toggle("Use monospaced font in bulk recipe ingredient and direction edit forms", isOn: $monospacedBulkEditFont)
            } header: {
                Text(platformSpecificHeadingName("View Options"))
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
                Text(platformSpecificHeadingName("Database Backups"))
                    #if os(macOS)
                    .font(.headline)
                    .bold()
                    .padding(.top, 8)
                    #endif
            }
            
            Section {
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
            } header: {
                Text(platformSpecificHeadingName("Image Cleanup"))
                    #if os(macOS)
                    .font(.headline)
                    .bold()
                    .padding(.top, 8)
                    #endif
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
