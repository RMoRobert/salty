//
//  DatabaseLocationViewModel.swift
//  Salty
//
//  Choosing the folder Salty keeps its library in. The choice is checked off the main actor (a
//  library is created there, or an existing one opened and migrated), then saved for the next launch.
//  The running app keeps the library it opened until it restarts.
//

import Foundation
import OSLog

@MainActor
@Observable
final class DatabaseLocationViewModel {
    private(set) var isOpening = false
    /// The library this session is using.
    let currentLocation = FileManager.saltyLibraryDirectory
    /// The library the next launch will use, once a different one has been chosen.
    private(set) var pendingLocation: URL?
    var showingSuccessAlert = false
    var showingErrorAlert = false
    private(set) var errorMessage = ""

    @ObservationIgnored private let logger = Logger(subsystem: "Salty", category: "FileAccess")

    /// The folder picker failed before a folder was chosen.
    func folderSelectionFailed(_ error: Error) {
        logger.error("\(error.localizedDescription)")
        fail("Failed to select folder: \(error.localizedDescription)")
    }

    /// Makes `url` the library folder from the next launch, creating a library there if it has none.
    /// Nothing is saved unless the check passes, so a folder that can't hold a library changes nothing.
    func openDatabase(at url: URL) async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        logger.debug("Starting database open...")

        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Unable to startAccessingSecurityScopedResource for \(url)")
            fail("Unable to access the selected folder. Please try again.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let file = try FileManager.libraryDatabaseFile(inParent: url)
            // Off the main actor: migrating a large library can take a while, and "Opening database…"
            // should be drawn meanwhile.
            try await Task.detached(priority: .userInitiated) {
                try checkLibrary(atPath: file.path)
            }.value
            // Saved last, while this method still holds the folder's security scope (the bookmark
            // needs it).
            try FileManager.saveCustomLocationBookmarks(parentDirectory: url)
            pendingLocation = FileManager.libraryDirectory(inParent: url)
            showingSuccessAlert = true
        } catch {
            logger.error("Unable to switch database location: \(error.localizedDescription)")
            fail("Failed to open a library in the selected folder: \(error.localizedDescription)")
        }
    }

    /// Uses the default location from the next launch, as Settings → Database does.
    func revertToDefaultLocation() {
        FileManager.clearCustomLocationBookmarks()
        pendingLocation = FileManager.defaultSaltyLibraryDirectory
        showingSuccessAlert = true
    }

    private func fail(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }
}
