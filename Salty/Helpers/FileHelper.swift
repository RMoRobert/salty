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
    
    static let userDocumentsDirectory = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    static let defaultSaltyLibraryDirectory = FileManager.userDocumentsDirectory()
        .appendingPathComponent("Salty Recipe Library", isDirectory: true)
        .appendingPathComponent(folderName, isDirectory: true)
        .appendingPathExtension(folderBundleExt)
    
    // MARK: - Custom Location Access (Multiple Bookmarks)
    
    static var customParentDirectory: URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "databaseParentLocation") else {
            return nil
        }
        var wasStale = false
        guard let parentLocation = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve databaseParentLocation")
            return nil
        }
        if wasStale {
            refreshBookmark(for: "databaseParentLocation", at: parentLocation)
        }
        return parentLocation
    }
    
    static var customDatabaseBundleDirectory: URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "databaseBundleLocation") else {
            return nil
        }
        var wasStale = false
        guard let bundleLocation = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve databaseBundleLocation")
            return nil
        }
        if wasStale {
            refreshBookmark(for: "databaseBundleLocation", at: bundleLocation)
        }
        return bundleLocation
    }
    
    static var customImagesDirectory: URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "imagesLocation") else {
            return nil
        }
        var wasStale = false
        guard let imagesLocation = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve imagesLocation")
            return nil
        }
        if wasStale {
            refreshBookmark(for: "imagesLocation", at: imagesLocation)
        }
        return imagesLocation
    }
    
    // Legacy support - will be removed
    static var customSaltyLibraryDirectory: URL? {
        return customParentDirectory
    }
    
    static let saltyLibraryDirectory = customParentDirectory ?? defaultSaltyLibraryDirectory

    static var defaultSaltyLibraryFullPath: URL {
        let libDir = defaultSaltyLibraryDirectory
        try? FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        return libDir
            .appendingPathComponent(dbFileName, isDirectory: false)
            .appendingPathExtension(dbFileExt)
    }
    
    static let saltyImageFolderName = "recipeImages"
    
    static var saltyImageFolderUrl: URL {
        // Use specific images bookmark if available, otherwise fall back to default structure
        if let customImages = customImagesDirectory {
            return customImages
        } else {
            return saltyLibraryDirectory
                .appendingPathComponent(saltyImageFolderName, isDirectory: true)
        }
    }

    static var customSaltyLibraryFullPath: URL? {
        // Use the specific database bundle bookmark for direct access
        if let bundleLocation = customDatabaseBundleDirectory {
            let didStart = bundleLocation.startAccessingSecurityScopedResource()
            defer { if didStart { bundleLocation.stopAccessingSecurityScopedResource() } }
            
            let fullLocation = bundleLocation
                .appendingPathComponent(dbFileName, isDirectory: false)
                .appendingPathExtension(dbFileExt)
            
            let fileExists = FileManager.default.fileExists(atPath: fullLocation.path)
            if fileExists {
                print("Custom database file found at: \(fullLocation.path)")
                return fullLocation
            } else {
                print("Custom database file not found in bundle location")
            }
        }
        
        // Fallback to default location
        print("Reverting to default database location")
        return defaultSaltyLibraryFullPath
    }
    
    static var saltyLibraryFullPath: URL {
        let path = customSaltyLibraryFullPath ?? defaultSaltyLibraryFullPath
        print("Opening database at path: \(path)")
        return path
    }
    
    /// Returns the appropriate backup directory URL based on whether a custom location is set
    static var backupDirectory: URL {
        // If user has a custom database location, put backups in that same location
        if let customLocation = customParentDirectory {
            return customLocation.appendingPathComponent(backupFolderName, isDirectory: true)
        } else {
            // Otherwise, put backups in the default "Salty Recipe Library" folder
            let defaultLocation = defaultSaltyLibraryDirectory.deletingLastPathComponent()
            return defaultLocation.appendingPathComponent(backupFolderName, isDirectory: true)
        }
    }
    
    // MARK: - Bookmark Management
    
    private static func refreshBookmark(for key: String, at url: URL) -> Bool {
        do {
            let newBookmarkData = try url.bookmarkData(options: [])
            UserDefaults.standard.set(newBookmarkData, forKey: key)
            print("Refreshed stale bookmark for \(key)")
            return true
        } catch {
            print("Failed to refresh bookmark for \(key): \(error)")
            return false
        }
    }
    
    /// Saves multiple bookmarks for different components of the database location
    static func saveCustomLocationBookmarks(parentDirectory: URL) throws {
        // Create the expected directory structure
        let bundleDirectory = parentDirectory
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathExtension(folderBundleExt)
        
        let imagesDirectory = parentDirectory
            .appendingPathComponent(saltyImageFolderName, isDirectory: true)
        
        // Save bookmarks for each component
        let parentBookmark = try parentDirectory.bookmarkData(options: [])
        let bundleBookmark = try bundleDirectory.bookmarkData(options: [])
        let imagesBookmark = try imagesDirectory.bookmarkData(options: [])
        
        UserDefaults.standard.set(parentBookmark, forKey: "databaseParentLocation")
        UserDefaults.standard.set(bundleBookmark, forKey: "databaseBundleLocation")
        UserDefaults.standard.set(imagesBookmark, forKey: "imagesLocation")
        
        print("Saved bookmarks for parent: \(parentDirectory.path)")
        print("Saved bookmarks for bundle: \(bundleDirectory.path)")
        print("Saved bookmarks for images: \(imagesDirectory.path)")
    }
    
    /// Clears all custom location bookmarks
    static func clearCustomLocationBookmarks() {
        UserDefaults.standard.removeObject(forKey: "databaseParentLocation")
        UserDefaults.standard.removeObject(forKey: "databaseBundleLocation")
        UserDefaults.standard.removeObject(forKey: "imagesLocation")
        print("Cleared all custom location bookmarks")
    }
    
    // MARK: - Security-Scoped Resource Management
    
    /// Checks if the custom database location is accessible and refreshes the bookmark if needed
    static func validateAndRefreshCustomDatabaseAccess() -> Bool {
        guard let customLocation = customParentDirectory else {
            return false
        }
        
        // Try to access the security-scoped resource
        guard customLocation.startAccessingSecurityScopedResource() else {
            print("Failed to start accessing security-scoped resource for custom database location")
            return false
        }
        defer { customLocation.stopAccessingSecurityScopedResource() }
        
        // Check if we can read the directory contents
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: customLocation,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles]
            )
            print("Successfully accessed custom database location with \(contents.count) items")
            return true
        } catch {
            print("Failed to access custom database location: \(error)")
            return false
        }
    }
    
    /// Attempts to refresh a stale bookmark for the custom database location
    static func refreshCustomDatabaseBookmark() -> Bool {
        // Try to refresh all bookmarks
        var success = true
        
        if let parentLocation = customParentDirectory {
            success = success && refreshBookmark(for: "databaseParentLocation", at: parentLocation)
        }
        
        if let bundleLocation = customDatabaseBundleDirectory {
            success = success && refreshBookmark(for: "databaseBundleLocation", at: bundleLocation)
        }
        
        if let imagesLocation = customImagesDirectory {
            success = success && refreshBookmark(for: "imagesLocation", at: imagesLocation)
        }
        
        return success
    }
    
    /// Validates that the database file exists and is accessible
    static func validateDatabaseAccess() -> Bool {
        let databasePath = saltyLibraryFullPath
        
        // For custom locations, ensure we have proper access
        if customParentDirectory != nil {
            guard validateAndRefreshCustomDatabaseAccess() else {
                print("Failed to validate custom database access")
                return false
            }
        }
        
        // Check if the database file exists
        guard FileManager.default.fileExists(atPath: databasePath.path) else {
            print("Database file does not exist at: \(databasePath.path)")
            
            // Additional diagnostics for iOS/iCloud issues
            if customParentDirectory != nil {
                print("This appears to be a custom location. Checking directory contents...")
                do {
                    let directoryPath = databasePath.deletingLastPathComponent()
                    let contents = try FileManager.default.contentsOfDirectory(at: directoryPath, includingPropertiesForKeys: [.nameKey])
                    print("Directory contents: \(contents.map { $0.lastPathComponent })")
                    
                    // Check if the database file exists with a different name
                    let dbFiles = contents.filter { $0.lastPathComponent.contains("saltyRecipeDB") }
                    if !dbFiles.isEmpty {
                        print("Found potential database files: \(dbFiles.map { $0.lastPathComponent })")
                    }
                } catch {
                    print("Error checking directory contents: \(error)")
                }
            }
            return false
        }
        
        // Try to read the database file to ensure we have proper access
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: databasePath.path)
            print("Database file is accessible, size: \(attributes[.size] ?? 0) bytes")
            return true
        } catch {
            print("Failed to access database file: \(error)")
            return false
        }
    }
    
    /// Provides detailed diagnostic information about database access
    static func getDatabaseAccessDiagnostics() -> [String: Any] {
        var diagnostics: [String: Any] = [:]
        
        // Check if using custom location
        let isCustomLocation = customParentDirectory != nil
        diagnostics["isCustomLocation"] = isCustomLocation
        
        if isCustomLocation {
            diagnostics["customLocationPath"] = customParentDirectory?.path ?? "Unknown"
            diagnostics["bundleLocationPath"] = customDatabaseBundleDirectory?.path ?? "Unknown"
            diagnostics["imagesLocationPath"] = customImagesDirectory?.path ?? "Unknown"
            
            // Check bookmark status for all bookmarks
            let bookmarkKeys = ["databaseParentLocation", "databaseBundleLocation", "imagesLocation"]
            for key in bookmarkKeys {
                if let bookmarkData = UserDefaults.standard.data(forKey: key) {
                    var wasStale = false
                    if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) {
                        diagnostics["\(key)_resolved"] = true
                        diagnostics["\(key)_wasStale"] = wasStale
                        diagnostics["\(key)_path"] = resolvedURL.path
                    } else {
                        diagnostics["\(key)_resolved"] = false
                    }
                } else {
                    diagnostics["\(key)_exists"] = false
                }
            }
        }
        
        // Check database file
        let databasePath = saltyLibraryFullPath
        diagnostics["databasePath"] = databasePath.path
        diagnostics["databaseExists"] = FileManager.default.fileExists(atPath: databasePath.path)
        
        if FileManager.default.fileExists(atPath: databasePath.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: databasePath.path)
                diagnostics["databaseSize"] = attributes[.size] ?? 0
                diagnostics["databasePermissions"] = attributes[.posixPermissions] ?? 0
            } catch {
                diagnostics["databaseAccessError"] = error.localizedDescription
            }
        }
        
        // Check directory permissions
        let directoryPath = databasePath.deletingLastPathComponent()
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directoryPath, includingPropertiesForKeys: [.nameKey])
            diagnostics["directoryAccessible"] = true
            diagnostics["directoryContentsCount"] = contents.count
        } catch {
            diagnostics["directoryAccessible"] = false
            diagnostics["directoryAccessError"] = error.localizedDescription
        }
        
        return diagnostics
    }
    
    /// Provides guidance for iOS/iCloud database selection
    static func getIOSDatabaseSelectionGuidance() -> String {
        return """
        For iOS/iCloud compatibility:
        
        1. On macOS: Select the folder containing your SaltyRecipeLibrary.saltyRecipeLibrary bundle
        2. On iOS: You must select the SaltyRecipeLibrary.saltyRecipeLibrary folder itself (not its parent)
        
        This ensures the app can access the database file while maintaining compatibility between platforms.
        """
    }
    
    /// Proactively refreshes bookmarks to prevent permission issues
    /// This should be called periodically (e.g., on app launch, before major operations)
    static func refreshBookmarksIfNeeded() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "databaseLocation") else {
            return // No custom location set
        }
        
        var wasStale = false
        guard let databaseLocation = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve bookmark data during proactive refresh")
            return
        }
        
        if wasStale {
            print("Proactively refreshing stale bookmark...")
            do {
                // Try to access the resource to refresh the bookmark
                guard databaseLocation.startAccessingSecurityScopedResource() else {
                    print("Failed to start accessing security-scoped resource during proactive refresh")
                    return
                }
                defer { databaseLocation.stopAccessingSecurityScopedResource() }
                
                // Create a new bookmark
                let newBookmarkData = try databaseLocation.bookmarkData(options: [])
                UserDefaults.standard.set(newBookmarkData, forKey: "databaseLocation")
                print("Successfully refreshed bookmark proactively")
            } catch {
                print("Failed to refresh bookmark proactively: \(error)")
            }
        }
    }
}
