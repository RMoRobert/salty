 //
//  ImportView.swift
//  Salty
//
//  Created by Robert on 7/9/23.
//

import SwiftUI

struct OpenDBView: View {
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
                        print(error.localizedDescription)
                        errorMessage = "Failed to select folder: \(error.localizedDescription)"
                        showingErrorAlert = true
                    }
                }
                .padding()
            }
            VStack {
                Text("A Salty recipe library must already exist at the selected location.")
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
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            
            VStack(spacing: 8) {
                Text("Current location: \(currentLocation.relativePath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    Text("To clear any custom location and use the default:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Revert to Default Location") {
                        UserDefaults.standard.removeObject(forKey: "databaseLocation")
                        showingSuccessAlert = true
                    }
                    .buttonStyle(.link)
                }
                .padding()
                
            }
    
            
            Button("Dismiss") {
               dismiss()
            }
            .buttonStyle(.link)
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
        print("Starting database open...")
        
        do {
            guard url.startAccessingSecurityScopedResource() else {
                print("Unable to startAccessingSecurityScopedResource for \(url)")
                errorMessage = "Unable to access the selected folder. Please try again."
                showingErrorAlert = true
                isOpening = false
                return
            }
            
            let urlBookmarkData = try url.bookmarkData(options: [])
            UserDefaults.standard.set(urlBookmarkData, forKey: "databaseLocation")
            print("Saved bookmark for database path: \(urlBookmarkData)")
            url.stopAccessingSecurityScopedResource()
            
            isOpening = false
            showingSuccessAlert = true
        } catch {
            print("Unable to save bookmark for database path: \(error.localizedDescription)")
            errorMessage = "Failed to save database location: \(error.localizedDescription)"
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
