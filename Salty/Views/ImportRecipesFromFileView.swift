//
//  ImportRecipesFromFileView.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import SwiftUI
import SQLiteData
import UniformTypeIdentifiers
import OSLog
import SaltyCore

struct ImportRecipesFromFileView: View {
    private let logger = Logger(subsystem: "Salty", category: "Import")
    @Dependency(\.defaultDatabase) private var database
    @Environment(\.dismiss) private var dismiss
    @State private var showingImportFilePicker = false
    @State private var selectedFileUrls: [URL] = []
    @State private var isImporting = false
    @State private var filesImported = 0
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var successMessage = ""

    // New parameter for pre-selected files
    let preSelectedFileURL: URL?

    // Default initializer for backward compatibility
    init() {
        self.preSelectedFileURL = nil
    }

    // New initializer for pre-selected files
    init(preSelectedFileURL: URL?) {
        self.preSelectedFileURL = preSelectedFileURL
    }

    /// Selected files Salty knows how to read, paired with their format. Crouton writes one file per
    /// recipe, so a real migration means selecting dozens of files at once; anything unrecognized is
    /// reported rather than silently guessed at.
    private var importableFiles: [(url: URL, kind: RecipeImportFileKind)] {
        selectedFileUrls.compactMap { url in
            RecipeImportFileKind(url: url).map { (url, $0) }
        }
    }

    private func startImport() {
        let files = importableFiles
        guard !files.isEmpty else { return }

        isImporting = true
        filesImported = 0
        logger.debug("Starting import of \(files.count) file(s)…")

        Task {
            var importedRecipeCount = 0
            var failedFileNames: [String] = []

            for file in files {
                let isScoped = file.url.startAccessingSecurityScopedResource()
                defer { if isScoped { file.url.stopAccessingSecurityScopedResource() } }

                do {
                    let importedIds: [String]
                    switch file.kind {
                    case .saltyRecipe:
                        importedIds = try await SaltyRecipeImportHelper.importIntoDatabase(database, jsonFileUrl: file.url)
                    case .macGourmet:
                        importedIds = try await MacGourmetImportHelper.importIntoDatabase(database, xmlFileUrl: file.url)
                    case .crouton:
                        importedIds = try await CroutonImportHelper.importIntoDatabase(database, fileUrl: file.url)
                    }
                    importedRecipeCount += importedIds.count
                } catch {
                    logger.error("Import of \(file.url.lastPathComponent) failed: \(error.localizedDescription)")
                    failedFileNames.append(file.url.lastPathComponent)
                }

                await MainActor.run { filesImported += 1 }
            }

            await MainActor.run {
                logger.debug("Done importing: \(importedRecipeCount) recipes, \(failedFileNames.count) file(s) failed")
                isImporting = false

                if importedRecipeCount == 0 {
                    errorMessage = "No recipes could be imported from the selected \(files.count == 1 ? "file" : "files")."
                    showingErrorAlert = true
                    return
                }

                successMessage = Self.summaryMessage(
                    recipeCount: importedRecipeCount,
                    fileCount: files.count,
                    failedFileNames: failedFileNames
                )
                showingSuccessAlert = true
            }
        }
    }

    /// Reports both counts, because they diverge in both directions: one .mgourmet file can hold a
    /// whole library, while a Crouton export is one recipe per file.
    nonisolated static func summaryMessage(recipeCount: Int, fileCount: Int, failedFileNames: [String]) -> String {
        let recipes = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        let files = fileCount == 1 ? "1 file" : "\(fileCount) files"
        var message = "Imported \(recipes) from \(files)."

        if !failedFileNames.isEmpty {
            let skipped = failedFileNames.count == 1 ? "1 file" : "\(failedFileNames.count) files"
            message += "\n\nCould not read \(skipped): \(failedFileNames.prefix(5).joined(separator: ", "))"
            if failedFileNames.count > 5 {
                message += ", and \(failedFileNames.count - 5) more"
            }
        }

        return message
    }

    var body: some View {
        let chooseFileButton: some View = Button(selectedFileUrls.isEmpty ? "Choose Files…" : "Choose Other Files…") {
            showingImportFilePicker.toggle()
        }
            .fileImporter(
                isPresented: $showingImportFilePicker,
                allowedContentTypes: [.data, .saltyRecipe],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let files):
                    selectedFileUrls = files
                case .failure(let error):
                    logger.error("\(error.localizedDescription)")
                    errorMessage = "Failed to select files: \(error.localizedDescription)"
                    showingErrorAlert = true
                }
            }

        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Import Recipes")
                    .font(.title2)
                    .fontWeight(.semibold)

                if !selectedFileUrls.isEmpty {
                    ImportSelectionSummaryView(
                        fileUrls: selectedFileUrls,
                        importableCount: importableFiles.count,
                        kinds: Array(Set(importableFiles.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
                    )
                    chooseFileButton
                }
                else {
                    Text("No files selected")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }

            // File selection
            if selectedFileUrls.isEmpty {
                chooseFileButton
            }
            // Description
            Text("Import Salty (.saltyRecipe), MacGourmet (.mgourmet), or Crouton (.crumb) files into your recipe library.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Import section
            if !selectedFileUrls.isEmpty {
                VStack(spacing: 16) {
                    if isImporting {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Importing recipes...")
                                .font(.headline)
                            if importableFiles.count > 1 {
                                Text("File \(filesImported + 1) of \(importableFiles.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Please wait while we import your recipes.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding()
                    } else if importableFiles.isEmpty {
                        Text("Unsupported file type. Please select .saltyRecipe, .mgourmet, or .crumb files.")
                            .padding()
                            .foregroundStyle(.orange)
                    } else {
                        Button(importableFiles.count == 1 ? "Import Recipe" : "Import \(importableFiles.count) Files") {
                            startImport()
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
            logger.debug("ImportRecipesFromFileView appeared")
            logger.debug("preSelectedFileURL: \(String(describing: preSelectedFileURL))")
            // Set the pre-selected file URL if provided
            if let preSelectedURL = preSelectedFileURL {
                selectedFileUrls = [preSelectedURL]
                logger.debug("Set selectedFileUrls to: \(preSelectedURL)")
            }
        }
        .alert("Import Complete", isPresented: $showingSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(successMessage)
        }
        .alert("Import Failed", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
}

/// Names the selected file (or counts them), and the format(s) Salty recognized.
private struct ImportSelectionSummaryView: View {
    let fileUrls: [URL]
    let importableCount: Int
    let kinds: [RecipeImportFileKind]

    private var unsupportedCount: Int { fileUrls.count - importableCount }

    var body: some View {
        VStack(spacing: 4) {
            if let onlyFile = fileUrls.first, fileUrls.count == 1 {
                Text("File: \(onlyFile.lastPathComponent)")
                    .font(.headline)
            } else {
                Text("\(fileUrls.count) files selected")
                    .font(.headline)
            }

            if !kinds.isEmpty {
                Text("Type: \(kinds.map(\.displayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if unsupportedCount > 0 {
                Text("\(unsupportedCount) unsupported \(unsupportedCount == 1 ? "file" : "files") will be skipped")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }
}

#Preview {
    ImportRecipesFromFileView()
}
