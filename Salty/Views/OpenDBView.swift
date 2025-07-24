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
    @State private var selectedUrl: URL?
    @State private var hasSelected = false
    @State private var isOpening = false
    @State private var hasOpened = false
    @State private var currentLocation = FileManager.saltyLibraryDirectory
    
    var body: some View {
        VStack {
            VStack {
                if let importUrl = selectedUrl?.relativePath {
                    Text("Open: \(importUrl)")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                        .padding()
                }
                else {
                    Text("Open:")
                        .padding()
                }
                Button("Choose Database…") {  showingFolderPicker.toggle() }
                    .fileImporter(
                        isPresented: $showingFolderPicker,
                        allowedContentTypes: [.folder]
                    ) { result in
                        switch result {
                        case .success(let url):
                            selectedUrl = url
                            hasSelected = true
                        case .failure(let error):
                            print(error.localizedDescription)
                            hasSelected = false
                        }
                    }
                    .padding()
            }
            VStack {
                Text("Select the Salty recipe library folder to open above. (Library must already exist at this location.)")
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
                    .padding()
            }
            Spacer()
            if let folder = selectedUrl {
                if !hasOpened {
                    Button("Open") {
                        isOpening = true
                        print("Starting database open...")
                        do {
                            guard folder.startAccessingSecurityScopedResource() else {
                                print("Unable to startAccessingSecurityScopedResource for \(folder)")
                                return
                            }
                                let urlBookmarkData = try
                                
                            folder.bookmarkData(options: [])
                                UserDefaults.standard.set(urlBookmarkData, forKey: "databaseLocation")
                                print("Saved bookmark for database path: \(urlBookmarkData)")
                                folder.stopAccessingSecurityScopedResource()
                            }
                        catch {
                            print("Unable to save bookmark for database path: \(error.localizedDescription)")
                        }
                        isOpening = false
                        hasOpened = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                if (isOpening) {
                    HStack {
                        ProgressView()
                        Text("Opening...please wait")
                    }
                    .padding()
                }
                else if (hasOpened) {
                    Text("Opened! Restart Salty to use new database location.")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                        .fontWeight(.bold)
                        .padding()
                }
            }
            
            else {
                Text("Select database location above.")
                    .padding()
            }
            
            VStack {
                Text("Current location: \(currentLocation.relativePath)")
                    .font(.footnote)
                Button("Revert to default location") {
                    UserDefaults.standard.removeObject(forKey: "databaseLocation")
                    selectedUrl = nil
                    hasOpened = false
                    hasSelected = false
                }
                Text("Will clear any previously saved custom locations and use the default location")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
    
            
            Button("Dismiss") {
               dismiss()
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(idealWidth: 350, maxWidth: 400, idealHeight: 300)
    }
}

struct OpenDBView_Previews: PreviewProvider {
    static var previews: some View {
        OpenDBView()
    }
}
