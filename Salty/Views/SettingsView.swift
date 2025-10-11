//
//  SettingsView.swift
//  Salty
//
//  Created by Robert on 7/6/25.
//

import SwiftUI
import SQLiteData

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

struct DatabaseSettingsView: View {
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
                    .cornerRadius(4)
                
                Button("Reset to Default Location", role: .destructive) {
                    showingResetConfirmation = true
                }
                #if os(macOS)
                .buttonStyle(.link)
                #endif
            } header: {
                Text("Database Location")
                    #if os(macOS)
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.top, 8)
                    #endif
            }
            
            Section {
                DisclosureGroup(isExpanded: $isDiagnosticsExpanded) {
                    Text(FileManager.getDatabaseTroubleshootingGuidance())
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                Text("Database Diagnostics")
                    #if os(macOS)
                    .font(.headline)
                    .fontWeight(.bold)
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
        print("Reset database location to default")
        // Refresh diagnostics after reset
        diagnosticsInfo = FileManager.getDatabaseAccessDiagnostics()
    }
}

struct GeneralSettingsView: View {
    @AppStorage("webPreviews") private var useWebRecipeDetailView = false
    @AppStorage("mobileEditViews") private var useMobileEditViews = false
    @AppStorage("monospacedBulkEditFont") private var monospacedBulkEditFont = false
    
    var body: some View {
        Form {
// TODO: Consider addin g this back some day
//            Toggle("Use web-based recipe detail view (instead of native UI-based view)", isOn: $useWebRecipeDetailView)
            Toggle("Use monospaced font in bulk recipe ingredient and direction edit forms", isOn: $monospacedBulkEditFont)
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
                    .foregroundColor(.secondary)
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
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Database Backups")
                    #if os(macOS)
                    .font(.headline)
                    .fontWeight(.bold)
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
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Image Cleanup")
                    #if os(macOS)
                    .font(.headline)
                    .fontWeight(.bold)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCreatingBackup = false
            backupMessage = "Backup created successfully!"
            
            // Clear the message after a couple seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
                .foregroundColor(.primary)
            
            Text("\(value ?? "nil")")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }
}


#Preview {
    SettingsView()
}
