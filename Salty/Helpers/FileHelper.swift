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

//    static var customSaltyLibraryFullPath: URL {
//        var baseURL: URL?
//        var wasStale = false
//        if let recipeDBBookmark = UserDefaults.standard.data(forKey: "RecipeDBBookmark") {
//            try? baseURL = URL(resolvingBookmarkData: recipeDBBookmark, options: [.withoutUI, .withSecurityScope], bookmarkDataIsStale: &wasStale)
//            if (wasStale) {
//                if let baseURL = baseURL {
//                    UserDefaults.standard.set(baseURL.absoluteString, forKey: "recipeDBPathString")
//                }
//            }
//        }
//        else {
//            baseURL = defaultSaltyLibraryDirectory
//        }
//        try? FileManager.default.createDirectory(at: baseURL!, withIntermediateDirectories: true)
//        baseURL!.startAccessingSecurityScopedResource()
//        defer { baseURL!.stopAccessingSecurityScopedResource() }
//        print("baseURL = \(baseURL?.absoluteString)")
//        return baseURL!
//                .appendingPathComponent(dbFileName)
//                .appendingPathExtension(dbFileExt)
//    }
}
