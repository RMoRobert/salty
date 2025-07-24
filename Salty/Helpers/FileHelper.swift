//
//  FileHelper.swift
//  Salty
//
//  Created by Robert on 5/30/23.
//

import Foundation

extension FileManager {
    static let folderName = "SaltyRecipeLibrary"
    static let folderBundleExt = "saltyRecipeLibrary"
    static let dbFileName = "saltyRecipeDB"
    static let dbFileExt = "sqlite"
    static let backupFolderName = "Backup"
    
    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    static let defaultSaltyLibraryDirectory = FileManager.getDocumentsDirectory()
        .appendingPathComponent("Salty Recipe Library", isDirectory: true)
        .appendingPathComponent(folderName, isDirectory: true)
        .appendingPathExtension(folderBundleExt)
    
    static var customSaltyLibraryDirectory: URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "databaseLocation") else {
            print("No databaseLocation; returning")
            return nil
        }
        var wasStale = false
        guard let databaseLocation = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve databaseLocation")
            return nil
        }
        if (wasStale) {
            do {
                let newBookmarkData = try databaseLocation.bookmarkData(
                    options: []
                )
                UserDefaults.standard.set(newBookmarkData, forKey: "databaseLocation")
                print("Refreshed stale bookmark and saved new bookmark data.")
            } catch {
                print("Failed to refresh stale bookmark: \(error)")
            }
        }
        return databaseLocation
    }
    
    static let saltyLibraryDirectory = customSaltyLibraryDirectory ?? defaultSaltyLibraryDirectory

    static var defaultSaltyLibraryFullPath: URL {
        let libDir = defaultSaltyLibraryDirectory
        try? FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        return libDir
            .appendingPathComponent(dbFileName, isDirectory: false)
            .appendingPathExtension(dbFileExt)
    }
    
    static let saltyImageFolderName = "recipeImages"
    
    static var saltyImageFolderUrl: URL {
        return saltyLibraryDirectory
            .appendingPathComponent(saltyImageFolderName, isDirectory: true)
    }

    static var customSaltyLibraryFullPath: URL? {
        let databaseLocation = saltyLibraryDirectory
        let didStart = databaseLocation.startAccessingSecurityScopedResource()
        defer { if didStart { databaseLocation.stopAccessingSecurityScopedResource() } }
        print("databaseLocation = \(databaseLocation.absoluteString)")
        
        // Look for the database file inside the SaltyRecipeLibrary.saltyRecipeLibrary bundle
        var fullLocation = databaseLocation
                .appendingPathComponent(folderName, isDirectory: true)
                .appendingPathExtension(folderBundleExt)
                .appendingPathComponent(dbFileName, isDirectory: false)
                .appendingPathExtension(dbFileExt)        
        if !FileManager.default.fileExists(atPath: fullLocation.path) {
            print("Custom database specified but not found; revering to default")
            fullLocation = defaultSaltyLibraryFullPath
        }
        return fullLocation
    }
    
    static var saltyLibraryFullPath: URL {
        let path = customSaltyLibraryFullPath ?? defaultSaltyLibraryFullPath
        print("Opening database at path: \(path)")
        return path
    }
    
    /// Returns the appropriate backup directory URL based on whether a custom location is set
    static var backupDirectory: URL {
        // If user has a custom database location, put backups in that same location
        if let customLocation = customSaltyLibraryDirectory {
            return customLocation.appendingPathComponent(backupFolderName, isDirectory: true)
        } else {
            // Otherwise, put backups in the default "Salty Recipe Library" folder
            let defaultLocation = defaultSaltyLibraryDirectory.deletingLastPathComponent()
            return defaultLocation.appendingPathComponent(backupFolderName, isDirectory: true)
        }
    }
}
