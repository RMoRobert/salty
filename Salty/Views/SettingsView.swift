//
//  SettingsView.swift
//  Salty
//
//  Created by Robert on 7/6/25.
//

import SwiftUI
import SharingGRDB

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
        .frame(maxWidth: 450, minHeight: 200)
        #endif
        .onAppear {
            diagnosticsInfo = FileManager.getDatabaseAccessDiagnostics()
        }
    }
}

struct DatabaseSettingsView: View {
    @Binding var diagnosticsInfo: [String: Any]
    @State private var showingResetConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Troubleshooting Guidance Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status & Guidance")
                        .font(.headline)
                    
                    Text(FileManager.getDatabaseTroubleshootingGuidance())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
                
                Divider()
                
                // Database Location Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Database Location")
                        .font(.headline)
                    
                    if FileManager.customSaltyLibraryDirectory != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Custom Location")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Parent Directory:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(FileManager.customSaltyLibraryDirectory?.path ?? "Unknown")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Database Bundle:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(FileManager.customSaltyLibraryDirectory?.path ?? "Unknown")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Images Directory:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(FileManager.customImagesDirectory?.path ?? "Unknown")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Button("Reset to Default Location", role: .destructive) {
                                showingResetConfirmation = true
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Default Location")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(FileManager.defaultDatabaseBundleFullPath.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
                
                Divider()
                
                // Diagnostics Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Database Diagnostics")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button("Refresh") {
                            diagnosticsInfo = FileManager.getDatabaseAccessDiagnostics()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(diagnosticsInfo.keys.sorted()), id: \.self) { key in
                            DiagnosticRow(key: key, value: diagnosticsInfo[key])
                        }
                    }
                }
            }
            .padding()
        }
        .alert("Reset Database Location", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefaultDatabaseLocation()
            }
        } message: {
            Text("This will reset your database location to the default location. You'll need to restart the app for changes to take effect.")
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
            Toggle("Use web-based recipe detail view (instead of native UI-based view)", isOn: $useWebRecipeDetailView)
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
        VStack(alignment: .leading, spacing: 16) {
            // Backup Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Database Backups")
                    .font(.headline)
                
                Text("Salty automatically creates and stores up to a few recent backups of your recipe library.")
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
            }
            
            Divider()
            
            // Image Cleanup Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Image Cleanup")
                    .font(.headline)
                
                Button("Clean Up Orphaned Images") {
                    print("TO DO!")
                    //RecipeImageManager.shared.cleanupOrphanedImages()
                }
                .buttonStyle(.bordered)
                
                Text("COMING SOON: This will remove all images stored alongside your recipe library database that are not referenced in the database. It should be safe, but we suggest having a backup before running (as you should periodically regardless).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .alert("Delete All Backups", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllBackups()
            }
        } message: {
            Text("This will permanently delete all backup files. This action cannot be undone.")
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
            
            // Clear the message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
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
            
            // Clear the message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
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
