//
//  OpenDBView.swift
//  Salty
//
//  Created by Robert on 7/9/23.
//

import SwiftUI

struct OpenDBView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingFolderPicker = false
    @State private var viewModel = DatabaseLocationViewModel()
    
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
                .disabled(viewModel.isOpening)
                .fileImporter(
                    isPresented: $showingFolderPicker,
                    allowedContentTypes: [.folder]
                ) { result in
                    switch result {
                    case .success(let url):
                        Task { await viewModel.openDatabase(at: url) }
                    case .failure(let error):
                        viewModel.folderSelectionFailed(error)
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
            
            if viewModel.isOpening {
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
                Text("Current location: \(viewModel.currentLocation.relativePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let pending = viewModel.pendingLocation {
                    Text("After restarting: \(pending.relativePath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack(spacing: 8) {
                    Text("To clear any custom location and use the default:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Revert to Default Location") {
                        viewModel.revertToDefaultLocation()
                    }
                    .disabled(viewModel.isOpening)
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
        .alert("Database Location Updated", isPresented: $viewModel.showingSuccessAlert) {
            if AppRelauncher.isAvailable {
                Button("Relaunch Now") {
                    Task { await AppRelauncher.relaunch() }
                }
                Button("Later", role: .cancel) {
                    dismiss()
                }
            } else {
                Button("OK") {
                    dismiss()
                }
            }
        } message: {
            if AppRelauncher.isAvailable {
                Text("Salty will use the new location after it relaunches.")
            } else {
                Text("The database location has been updated. Close Salty from the app switcher and open it again to use the new location.")
            }
        }
        .alert("Error", isPresented: $viewModel.showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

struct OpenDBView_Previews: PreviewProvider {
    static var previews: some View {
        OpenDBView()
    }
}
