//
//  ImportView.swift
//  Salty
//
//  Created by Robert on 7/9/23.
//

import SwiftUI
import RealmSwift

struct OpenDBView: View {
    //@AppStorage("databaseLocation") var databaseLocation: URL?
    @State private var showingFolderPicker = false
    @State private var selectedUrl: URL?
    @State private var hasSelected = false
    @State private var isOpening = false
    @State private var hasOpened = false
    
    var body: some View {
        VStack {
            VStack {
                if let importUrl = selectedUrl?.relativePath {
                    Text("Open: \(importUrl)")
                }
                else {
                    Text("Open:")
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
            }
            VStack {
                Text("Select the Salty recipe library folder to open above.")
            }
            Spacer()
            if let folder = selectedUrl {
                Button("Open") {
                    // TODO
                    isOpening = true
                    print("Starting database open...")
                    //folder.startAccessingSecurityScopedResource()
                    if let urlBookmarkData = try? folder.bookmarkData(options: [.withSecurityScope]) {
                        
                        UserDefaults.standard.set(urlBookmarkData, forKey: "databaseLocation")
                    }
                    else {
                        print("Unable to save bookmark for database path.")
                    }
                    isOpening = false
                    hasOpened = true
                }
                .buttonStyle(.borderedProminent)
                if (isOpening) {
                    HStack {
                        ProgressView()
                        Text("Opening...please wait")
                    }
                }
                else if (hasOpened) {
                    Text("Opened! Restart Salty to use new database location.")
                }
            }
            else {
                Text("Select database location above.")
            }
        }
        .padding()
        .frame(idealWidth: 300, maxWidth: 400, idealHeight: 300)
    }
}

struct OpenDBView_Previews: PreviewProvider {
    static var previews: some View {
        OpenDBView()
    }
}
