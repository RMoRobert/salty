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
    @State private var hasImported = false
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
                        }
                        hasImported = false
                    }
            }
            VStack {
                Text("Select your MacGourgmet (.mgourmet) export file above, then select \"Import\" below to start importing into the current Salty recipe library.")
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
                         await MacGourmetImportHelper.importIntoDatabase(database, xmlFileUrl: file)
                         
                         await MainActor.run {
                             print("Done with import")
                             file.stopAccessingSecurityScopedResource()
                             isImporting = false
                             hasImported = true
                         }
                     }
                 }
                .buttonStyle(.borderedProminent)
                if (isImporting) {
                    HStack {
                        ProgressView()
                        Text("Importing...please wait")
                    }
                }
                else if (hasImported) {
                    Text("Imported!")
                }
            }
            else {
                Text("Select file above to import.")
                    .padding()
            }
            
            Button("Dismiss") {
               dismiss()
            }
            .buttonStyle(.borderless)
            
        }
        .padding()
        .frame(idealWidth: 400, maxWidth: 500, idealHeight: 300)
    }
}

#Preview {
    ImportRecipesFromFileView()
}
