//
//  FileHelper.swift
//  Salty
//
//  Created by Robert on 5/30/23.
//

import Foundation

extension FileManager {
    static let folderName = "Salty Recipe Library"
    static let folderBundleExt = "saltyRecipeLibrary"
    static let dbFileName = "SaltyRecipeDB"
    static let dbFileExt = "saltyRecipeDB"
    
    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    static let defaultSaltyLibraryDirectory = FileManager.getDocumentsDirectory()
        .appendingPathComponent(folderName, isDirectory: true)
        .appendingPathExtension(folderBundleExt)
    
    static var customSaltyLibraryDirectory: URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "databaseLocation") else {
            print("No databaseLocation; returning")
            return nil
        }
        var wasStale = false
    #if os(macOS)
        guard let databaseLocation = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve databaseLocation")
            return nil
        }
    #else
        guard let databaseLocation = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve databaseLocation")
            return nil
        }
    #endif
        if (wasStale) {
            print("databaseLocation was stale; TODO: update")
            //UserDefaults.standard.set(databaseLocation.absoluteString, forKey: "databaseLocation")
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
    
    static let saltyImageFolderName = "images"
    
    static var saltyImageFolderUrl: URL {
        return saltyLibraryDirectory
            .appendingPathComponent(saltyImageFolderName, isDirectory: true)
    }

    static var customSaltyLibraryFullPath: URL? {
        let databaseLocation = saltyLibraryDirectory
        #if os(macOS)
        databaseLocation.startAccessingSecurityScopedResource()
        #endif
        // defer { baseURL!.stopAccessingSecurityScopedResource() }
        print("databaseLocation = \(databaseLocation.absoluteString)")
        var fullLocation = databaseLocation
                .appendingPathComponent(dbFileName)
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
}
