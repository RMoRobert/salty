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

    static var defaultSaltyLibraryPath: URL {
        let libDir = defaultSaltyLibraryDirectory
        try? FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        return libDir
            .appendingPathComponent(dbFileName, isDirectory: false)
            .appendingPathExtension(dbFileExt)
    }
    
    static let saltyImageFolderName = "images"
    
    static var saltyImageFolderUrl: URL {
        return defaultSaltyLibraryDirectory
            .appendingPathComponent(saltyImageFolderName, isDirectory: true)
    }

    static var customSaltyLibraryFullPath: URL? {
        //return nil;
        //var wasStale = false
        guard let bookmarkData = UserDefaults.standard.data(forKey: "databaseLocation") else {
            print("No databaseLocation; returning")
            return nil
        }
        var wasStale = false
        guard let databaseLocation = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve databaseLocation")
            return nil
        }
        if (wasStale) {
            print("databaseLocation was stale; TODO: update")
            // UserDefaults.standard.set(databaseLocation.absoluteString, forKey: "databaseLocation")
        }
//        try? FileManager.default.createDirectory(at: databaseLocation, withIntermediateDirectories: true)
        databaseLocation.startAccessingSecurityScopedResource()
        // defer { baseURL!.stopAccessingSecurityScopedResource() }
        print("databaseLocation = \(databaseLocation.absoluteString)")
        return databaseLocation
                .appendingPathComponent(dbFileName)
                .appendingPathExtension(dbFileExt)
    }
    
    static var saltyLibraryPath: URL {
        let path = customSaltyLibraryFullPath ?? defaultSaltyLibraryPath
        print("Opening database at path: \(path)")
        return path
    }
}
