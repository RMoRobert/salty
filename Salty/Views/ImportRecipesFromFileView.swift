//
//  ImportRecipesFromFileView.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import SwiftUI
import SharingGRDB

struct ImportRecipesFromFileView: View {
    @Dependency(\.defaultDatabase) private var database
    @Environment(\.dismiss) private var dismiss
    @State private var showingImportFilePicker = false
    @State private var selectedFileUrl: URL?
    @State private var isImporting = false
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    var body: some View {
        VStack {
            VStack {
                if let importUrl = selectedFileUrl?.relativePath {
                    Text("Import from: \(importUrl)")
                        .padding()
                }
                else {
                    Text("Import from:")
                        .padding()
                }
                Button("Choose File…") {  showingImportFilePicker.toggle() }
                    .fileImporter(
                        isPresented: $showingImportFilePicker,
                        allowedContentTypes: [.data]
                    ) { result in
                        switch result {
                        case .success(let file):
                            selectedFileUrl = file
                        case .failure(let error):
                            print(error.localizedDescription)
                            errorMessage = "Failed to select file: \(error.localizedDescription)"
                            showingErrorAlert = true
                        }
                    }
            }
            VStack {
                Text("Choose your MacGourgmet (.mgourmet) export file above, then select \"Import\" below to start importing into the current Salty recipe library.")
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
                    .padding()
            }
            Spacer()
                         if let file = selectedFileUrl {
                 Button("Import") {
                     isImporting = true
                     print("Starting import...")
                     let _ = file.startAccessingSecurityScopedResource()
                     
                     Task {
                         do {
                             try await MacGourmetImportHelper.importIntoDatabase(database, xmlFileUrl: file)
                             
                             await MainActor.run {
                                 print("Done with import")
                                 file.stopAccessingSecurityScopedResource()
                                 isImporting = false
                                 showingSuccessAlert = true
                             }
                         } catch {
                             await MainActor.run {
                                 print("Import failed: \(error.localizedDescription)")
                                 file.stopAccessingSecurityScopedResource()
                                 isImporting = false
                                 errorMessage = "Import failed: \(error.localizedDescription)"
                                 showingErrorAlert = true
                             }
                         }
                     }
                 }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)
                
                if isImporting {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Importing recipes...")
                            .font(.headline)
                        Text("Please wait while we import your recipes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            else {
                Text("No file selected to import.")
                    .padding()
                    .foregroundColor(.secondary)
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
        .frame(idealWidth: 400, maxWidth: 500, idealHeight: 300)
        .alert("Import Complete", isPresented: $showingSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Successfully imported recipes from your MacGourmet file.")
        }
        .alert("Import Failed", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
}

#Preview {
    ImportRecipesFromFileView()
}
