//
//  ImportRecipesFromFileView.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import SwiftUI
import SQLiteData
import UniformTypeIdentifiers

struct ImportRecipesFromFileView: View {
    @Dependency(\.defaultDatabase) private var database
    @Environment(\.dismiss) private var dismiss
    @State private var showingImportFilePicker = false
    @State private var selectedFileUrl: URL?
    @State private var isImporting = false
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    // New parameter for pre-selected files
    let preSelectedFileURL: URL?
    
    // Default initializer for backward compatibility
    init() {
        self.preSelectedFileURL = nil
    }
    
    // New initializer for pre-selected files
    init(preSelectedFileURL: URL) {
        self.preSelectedFileURL = preSelectedFileURL
    }
    
    private var detectedFileType: String? {
        guard let file = selectedFileUrl else { return nil }
        let fileExtension = file.pathExtension.lowercased()
        switch fileExtension {
        case "saltyrecipe":
            return "Salty Recipe"
        case "mgourmet":
            return "MacGourmet"
        default:
            return nil
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Import Recipe")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let importUrl = selectedFileUrl?.lastPathComponent {
                    VStack(spacing: 4) {
                        Text("File: \(importUrl)")
                            .font(.headline)
                        if let fileType = detectedFileType {
                            Text("Type: \(fileType)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                else {
                    Text("No file selected")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            
            // File selection
            if selectedFileUrl == nil {
                Button("Choose File…") {  
                    showingImportFilePicker.toggle() 
                }
                .fileImporter(
                    isPresented: $showingImportFilePicker,
                    allowedContentTypes: [.data, .saltyRecipe]
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
            // Description
            Text("Import a MacGourmet (.mgourmet) or Salty (.saltyRecipe) file into your recipe library.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            // Import section
            if let file = selectedFileUrl {
                VStack(spacing: 16) {
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
                    } else {
                        Button("Import Recipe") {
                            isImporting = true
                            print("Starting import...")
                            let _ = file.startAccessingSecurityScopedResource()
                            
                            Task {
                                do {
                                    // Detect file type and use appropriate importer
                                    if file.pathExtension.lowercased() == "saltyrecipe" {
                                        try await SaltyRecipeImportHelper.importIntoDatabase(database, jsonFileUrl: file)
                                    } else {
                                        try await MacGourmetImportHelper.importIntoDatabase(database, xmlFileUrl: file)
                                    }
                                    
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
                        .disabled(detectedFileType == nil)
                    }
                }
            } else {
                if let file = selectedFileUrl, detectedFileType == nil {
                    Text("Unsupported file type. Please select a .mgourmet or .saltyRecipe file.")
                        .padding()
                        .foregroundColor(.orange)
                }
            }
            
            // Bottom buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding(.horizontal)
            
        }
        .padding()
        .onAppear {
            // Set the pre-selected file URL if provided
            if let preSelectedURL = preSelectedFileURL {
                selectedFileUrl = preSelectedURL
            }
        }
        .alert("Import Complete", isPresented: $showingSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Successfully imported recipes from your file.")
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
