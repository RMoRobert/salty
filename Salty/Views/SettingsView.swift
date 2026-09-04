//
//  SettingsView.swift
//  Salty
//
//  Created by Robert on 7/6/25.
//

import SwiftUI
import SQLiteData
import OSLog
import SaltyCore

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
    @AppStorage("autoSyncEnabled") private var autoSyncEnabled = false
    @State private var syncService = SaltySyncService.shared
    @State private var autoSync = AutoSyncCoordinator.shared
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""
    @State private var syncAlertTitle = ""
    @State private var showingPasswordPrompt = false
    @State private var isConnecting = false
    @State private var connectError: String?
    @State private var showingForceResyncConfirm = false
    @State private var showingForgetConfirm = false
    @State private var showingSaltyServerHelpAlert = false

    /// Whether the sync controls can do anything: this device is connected, or is one sync away from
    /// migrating a password saved by an earlier build into a sync token.
    private var canSync: Bool { syncService.hasCredentials }
    
    var body: some View {
        Form {
            Section {
                let serverToggle =
                Toggle("Enable sync with Salty Server", isOn: $serverUse)
                    .onChange(of: serverUse) { oldValue, newValue in
                        // Disabling sync doesn't forget the device, so the stored token is deliberately
                        // left alone; only a stale error message is worth clearing.
                        if !newValue { connectError = nil }
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
                    .disabled(!serverUse || canSync)
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
#endif

                // One action, in the row the password field used to occupy. Which one it is depends
                // on whether this device is connected, so there is never a dead control here.
                if canSync {
                    Button("Forget This Device", role: .destructive) {
                        showingForgetConfirm = true
                    }
#if os(macOS)
                    .buttonStyle(.link)
#else
                    .buttonStyle(.borderless)
#endif
                    .disabled(syncService.isSyncing)
                } else {
                    HStack {
                        Button("Connect This Device") { showingPasswordPrompt = true }
#if os(iOS)
                            .buttonStyle(.borderless)
#endif
                            .disabled(!serverUse || serverUrl.isEmpty
                                      || syncService.serverUsername.isEmpty || isConnecting)
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                if let connectError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(connectError)
                            .font(.caption)
                            .foregroundStyle(.red)
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
                    Text("Syncs in the background after you make changes, on launch, and when returning to the app. Repeated failures will show a dismissable banner to notify you (occasional failures are ignored).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button {
                        Task { await performSync() }
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
                    // Two buttons share this row, so on iOS each needs its own hit area rather than the
                    // whole-row tap a Form gives a lone button.
                    #if os(iOS)
                    .buttonStyle(.borderless)
                    #endif
                    .disabled(!serverUse || serverUrl.isEmpty || syncService.isSyncing || !canSync)

                    // Only offered for a regular sync -- a force re-sync empties one side before refilling
                    // it, so there's no safe point to stop it partway.
                    if syncService.isCancellable {
                        Spacer()
                        Button(syncService.isCancelling ? "Cancelling..." : "Cancel") {
                            syncService.cancelSync()
                        }
                        #if os(iOS)
                        .buttonStyle(.borderless)
                        #endif
                        .disabled(syncService.isCancelling)
                    }
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
                .disabled(!serverUse || serverUrl.isEmpty || syncService.isSyncing || !canSync)

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
                
                LastSyncedLabel(date: syncService.lastSyncDate)

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
        .alert(syncAlertTitle, isPresented: $showingSyncAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncAlertMessage)
        }
        .confirmationDialog("Force Full Re-Sync?", isPresented: $showingForceResyncConfirm, titleVisibility: .visible) {
            Button("Delete Local, Pull from Server", role: .destructive) {
                Task { await performForceResync() }
            }
            Button("Delete Server, Push from Local", role: .destructive) {
                Task { await performForcePush() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A full re-sync will delete all content from either the local device or the server and force a re-sync from the other direction. We suggest making a database backup before using this option. Please select a force-sync method.")
        }
        .confirmationDialog("Forget This Device?", isPresented: $showingForgetConfirm, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                Task { await forgetDevice() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This device will stop syncing until you connect it again. Your recipes stay on this device and on the server.")
        }
        .syncPasswordPrompt(isPresented: $showingPasswordPrompt,
                            username: syncService.serverUsername) { password in
            connectDevice(password: password)
        }
        .alert("What is Salty Server?", isPresented: $showingSaltyServerHelpAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Salty Server is an optional, self-hosted sync service you can add to sync your database among multiple devices (as an alternative to moving or copying the database file yourself or relying on third-party services). For details, see: https://github.com/rmorobert/saltyserver")
        }
    }
    
    /// Forgets this device, and says so only when the server couldn't be told.
    ///
    /// Success is silent: the row turns back into "Connect This Device", which is the confirmation.
    /// A failed revoke is worth a word, though, because the user is the only one who can finish the
    /// job -- and only they know whether this device is merely being reset or has gone missing.
    private func forgetDevice() async {
        let outcome = await syncService.signOut()
        connectError = nil
        if outcome == .localOnly {
            syncAlertTitle = "Forgotten on This Device"
            syncAlertMessage = "The server could not be reached to revoke your device's authorization, but local credentials have been deleted. You may wish to also manually remove this device from your active devices on your Salty Server instance if still active."
            showingSyncAlert = true
        }
    }

    /// Trades the password from the prompt for this device's sync token.
    ///
    /// The password arrives as a parameter and is never stored on this view, so it exists only for the
    /// duration of this call.
    private func connectDevice(password: String) {
        isConnecting = true
        connectError = nil
        Task {
            do {
                try await syncService.enroll(username: syncService.serverUsername, password: password)
                isConnecting = false
                syncAlertTitle = "Device Connected"
                syncAlertMessage = "This device is connected and ready to sync."
                showingSyncAlert = true
            } catch {
                connectError = friendlySyncMessage(error)
                isConnecting = false
            }
        }
    }

    private func performSync() async {
        do {
            // Settings is the deliberate, watch-it-happen sync, so it bypasses the recently-synced guard.
            try await syncService.syncNow(force: true)
            syncAlertTitle = "Sync Complete"
            syncAlertMessage = "Successfully synced with server.\n\(syncService.syncProgress.summary)"
            showingSyncAlert = true
        } catch {
            // A cancel is the user's own doing, so it gets a neutral title rather than "Sync Failed".
            syncAlertTitle = SyncError.isCancellation(error) ? "Sync Cancelled" : "Sync Failed"
            syncAlertMessage = friendlySyncMessage(error)
            showingSyncAlert = true
        }
    }

    private func performForceResync() async {
        do {
            try await syncService.forceFullResyncFromServer()
            syncAlertTitle = "Sync Complete"
            syncAlertMessage = "Full re-sync complete.\n\(syncService.syncProgress.summary)"
            showingSyncAlert = true
        } catch {
            syncAlertTitle = "Sync Failed"
            syncAlertMessage = friendlySyncMessage(error)
            showingSyncAlert = true
        }
    }

    private func performForcePush() async {
        do {
            try await syncService.forceFullResyncToServer()
            syncAlertTitle = "Sync Complete"
            syncAlertMessage = "Full re-sync complete.\n\(syncService.syncProgress.summary)"
            showingSyncAlert = true
        } catch {
            syncAlertTitle = "Sync Failed"
            syncAlertMessage = friendlySyncMessage(error)
            showingSyncAlert = true
        }
    }
}

/// "Last synced: …" line in Server settings. Re-renders when the wording is next due to change -- at the
/// 15-second mark, then on each minute boundary -- rather than polling at a fixed rate. The loop lives and
/// dies with the view, so nothing ticks while Settings is closed.
struct LastSyncedLabel: View {
    let date: Date?

    @State private var now = Date()

    var body: some View {
        HStack {
            Text("Last synced:")
            Text(date.map { LastSyncedDescription.text(for: $0, now: now) } ?? "Never")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .task(id: date) {
            guard let date else { return }
            while !Task.isCancelled {
                now = Date()
                // Half a second past the boundary, so the wake-up never lands just short of it and
                // immediately reschedules for a few more milliseconds.
                let interval = LastSyncedDescription.refreshInterval(for: date, now: now) + 0.5
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return  // view went away
                }
            }
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("mobileEditViews") private var useMobileEditViews = false
    @AppStorage("listViewStyle") private var listViewStyle: RecipeListViewStyle = .summary
    @AppStorage("sidebarShowFavorites") private var showFavorites = true
    @AppStorage("sidebarShowWantToMake") private var showWantToMake = true
    // The reorderable sections' own show/hide state lives in SidebarSectionVisibilityToggle; this holds
    // only their order.
    @AppStorage(SidebarSectionOrder.storageKey) private var sectionOrderRaw = ""

    private var sectionOrder: [SidebarSection] {
        SidebarSectionOrder.decode(sectionOrderRaw)
    }

    private func setOrder(_ order: [SidebarSection]) {
        sectionOrderRaw = SidebarSectionOrder.encode(order)
    }

    /// Only iOS gets the drag hint -- a grouped Form on macOS doesn't pick up `onMove`, so there the
    /// arrows are the only way to reorder.
    private var sidebarSectionsFooter: String {
        let intro = "These headings apppear after the Library items, in the order shown here."
        let rule = "At least one of Categories, Courses, or Tags must be enabled."
        #if os(macOS)
        return "\(intro) Use the arrows to reorder. \(rule)"
        #else
        return "\(intro) Use the arrows or hold and drag a row to reorder. \(rule)"
        #endif
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
            } header: {
                Text("Library Items")
                    #if os(macOS)
                    .padding(.top)
                    #endif
            } footer: {
                Text("These appear under All Recipes at the top of the sidebar.")
                    .font(.caption)
            }
            Section {
                let order = sectionOrder
                ForEach(order) { section in
                    SidebarSectionSettingsRow(
                        section: section,
                        canMoveUp: section != order.first,
                        canMoveDown: section != order.last,
                        move: { delta in
                            withAnimation {
                                setOrder(SidebarSectionOrder.moved(order, section, by: delta))
                            }
                        }
                    )
                }
                // Drag reordering, which a Form picks up on iOS but not on macOS.
                .onMove { fromOffsets, toOffset in
                    setOrder(SidebarSectionOrder.moved(order, fromOffsets: fromOffsets, toOffset: toOffset))
                }
            } header: {
                Text("Sidebar Sections")
                    #if os(macOS)
                    .padding(.top)
                    #endif
            } footer: {
                Text(sidebarSectionsFooter)
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

    var body: some View {
        Form {
            Section {
                Text("Salty automatically backs up your recipe library about every day and a half, keeping the two most recent backups plus a few older ones spaced days to weeks apart.")
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
    
    private func createBackupNow() {
        isCreatingBackup = true
        backupMessage = "Creating backup..."

        Task {
            // Report what actually happened: the message used to say "success" on a timer, whether or
            // not the backup had been written.
            do {
                let backupURL = try await backupManager.createBackupNow()
                backupMessage = "Backup created: \(backupURL.lastPathComponent)"
            } catch {
                backupMessage = "Backup failed: \(error.localizedDescription)"
            }
            isCreatingBackup = false

            // Clear a success message after a few seconds; leave a failure showing.
            if backupMessage.hasPrefix("Backup created") {
                try? await Task.sleep(for: .seconds(4))
                if backupMessage.hasPrefix("Backup created") {
                    backupMessage = ""
                }
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
