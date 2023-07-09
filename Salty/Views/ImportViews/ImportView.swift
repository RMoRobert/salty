//
//  ImportView.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import SwiftUI
import RealmSwift

struct ImportView: View {
    @ObservedResults(RecipeLibrary.self) var recipeLibraries
    @State private var showingImportFilePicker = false
    @State private var selectedFileUrl: URL?
    @State private var isImporting = false
    @State private var hasImported = false
    var body: some View {
        VStack {
            VStack {
                if let importUrl = selectedFileUrl?.relativePath {
                    Text("Import from: \(importUrl)")
                }
                else {
                    Text("Import from:")
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
            }
            Spacer()
            if let file = selectedFileUrl {
                Button("Import") {
                    guard let recipeLibrary = recipeLibraries.first else {
                        print("Error: no RecipeLibrary to import into")
                        return
                    }
                    isImporting = true
                    print("Starting import...")
                    MacGourmetImportHelper.importIntoRecipeLibrary(recipeLibrary, xmlFileUrl: file)
                    print("Done with import")
                    isImporting = false
                    hasImported = true
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
            }
        }
        .padding()
        .frame(idealWidth: 400, maxWidth: 500, idealHeight: 300)
    }
}

struct ImportView_Previews: PreviewProvider {
    static var previews: some View {
        ImportView()
    }
}
