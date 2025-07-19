//
//  SettingsView.swift
//  Salty
//
//  Created by Robert on 7/6/25.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Advanced", systemImage: "gearshape.2") {
                AdvancedSettingsView()
            }
        }
        .scenePadding()
        .frame(maxWidth: 450, minHeight: 200)
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


#Preview {
    SettingsView()
}
