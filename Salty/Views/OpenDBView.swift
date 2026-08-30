 //
//  ImportView.swift
//  Salty
//
//  Created by Robert on 7/9/23.
//

import SwiftUI
import OSLog

struct OpenDBView: View {
    private let logger = Logger(subsystem: "Salty", category: "FileAccess")
    @Environment(\.dismiss) private var dismiss
    @State private var showingFolderPicker = false
    @State private var isOpening = false
    @State private var currentLocation = FileManager.saltyLibraryDirectory
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack {
            VStack {
                Text("Select a Salty recipe library folder to open")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Button("Choose Database Folder…") { 
                    showingFolderPicker.toggle() 
                }
                .buttonStyle(.borderedProminent)
                .fileImporter(
                    isPresented: $showingFolderPicker,
                    allowedContentTypes: [.folder]
                ) { result in
                    switch result {
                    case .success(let url):
                        openDatabase(at: url)
                    case .failure(let error):
                        logger.error("\(error.localizedDescription)")
                        errorMessage = "Failed to select folder: \(error.localizedDescription)"
                        showingErrorAlert = true
                    }
                }
                .padding()
            }
            
            VStack(spacing: 8) {
                Text("If the selected folder doesn't already contain a Salty recipe library, a new one will be created there.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            if isOpening {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Opening database...")
                        .font(.headline)
                    Text("Please wait while we set up the new database location.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            
            VStack(spacing: 8) {
                Text("Current location: \(currentLocation.relativePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    Text("To clear any custom location and use the default:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Revert to Default Location") {
                        UserDefaults.standard.removeObject(forKey: FileManager.userDefaultsDatabaseParentLocationKey)
                        showingSuccessAlert = true
                    }
                    #if os(macOS)
                    .buttonStyle(.link)
                    #endif
                }
                .padding()
                
            }
    
            
            Button("Dismiss") {
               dismiss()
            }
            #if os(macOS)
            .buttonStyle(.link)
            #endif
            .padding()
        }
        .padding()
        .frame(idealWidth: 350, maxWidth: 400, idealHeight: 300)
        .alert("Database Location Updated", isPresented: $showingSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("The database location has been successfully updated. Please restart Salty to use the new location.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func openDatabase(at url: URL) {
        isOpening = true
        logger.debug("Starting database open...")

        // Remember the prior bookmark so a failed switch can be rolled back instead of leaving
        // the app pointed at a folder it can't use on next launch.
        let previousBookmark = UserDefaults.standard.data(forKey: FileManager.userDefaultsDatabaseParentLocationKey)

        do {
            guard url.startAccessingSecurityScopedResource() else {
                logger.error("Unable to startAccessingSecurityScopedResource for \(url)")
                errorMessage = "Unable to access the selected folder. Please try again."
                showingErrorAlert = true
                isOpening = false
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            try FileManager.saveCustomLocationBookmarks(parentDirectory: url)

            // Initialize the location now rather than at next launch: creates the library bundle
            // and schema in an empty folder (matching SaltyKMP), or opens and migrates a moved
            // library — so an unusable folder fails here in the dialog. The returned connection
            // is discarded; the app keeps using its current database until relaunch.
            _ = try appDatabase()

            isOpening = false
            showingSuccessAlert = true
        } catch {
            logger.error("Unable to switch database location: \(error.localizedDescription)")
            if let previousBookmark {
                UserDefaults.standard.set(previousBookmark, forKey: FileManager.userDefaultsDatabaseParentLocationKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FileManager.userDefaultsDatabaseParentLocationKey)
            }
            FileManager.refreshCustomDatabaseBookmark()
            errorMessage = "Failed to open a library in the selected folder: \(error.localizedDescription)"
            showingErrorAlert = true
            isOpening = false
        }
    }
}

struct OpenDBView_Previews: PreviewProvider {
    static var previews: some View {
        OpenDBView()
    }
}
