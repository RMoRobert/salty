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
    
    // MARK: - Custom Location Access (Single Parent Bookmark)
    
    static var customImagesDirectory: URL? {
        guard let parentLocation = customSaltyLibraryDirectory else {
            return nil
        }
        
        let imagesPath = parentLocation
            .appendingPathComponent(saltyImageFolderName, isDirectory: true)
        
        // Verify the images directory exists and is accessible
        if parentLocation.startAccessingSecurityScopedResource() {
            defer { parentLocation.stopAccessingSecurityScopedResource() }
            
            do {
                let parentContents = try FileManager.default.contentsOfDirectory(
                    at: parentLocation,
                    includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                let imagesExists = parentContents.contains { $0.lastPathComponent == saltyImageFolderName }
                
                if imagesExists {
                    return imagesPath
                } else {
                    print("Images directory '\(saltyImageFolderName)' not found in parent directory")
                    return nil
                }
            } catch {
                print("Error checking images directory: \(error)")
                return nil
            }
        } else {
            print("Cannot access parent directory to verify images directory")
            return nil
        }
    }
    
    // Legacy support - will be removed
    static var customSaltyLibraryDirectory: URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "databaseParentLocation") else {
            return nil
        }
        var wasStale = false
        guard let parentLocation = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve databaseParentLocation")
            return nil
        }
        if wasStale {
            let _ = refreshBookmark(for: "databaseParentLocation", at: parentLocation)
        }
        return parentLocation
    }
    
    static let saltyLibraryDirectory = customSaltyLibraryDirectory ?? defaultSaltyLibraryDirectory

    static var defaultDatabaseBundleFullPath: URL {
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

    static var customDatabaseBundleFullPath: URL? {
        // Derive the bundle path from the parent directory
        guard let parentLocation = customSaltyLibraryDirectory else {
            return nil
        }
        
        let bundlePath = parentLocation
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathExtension(folderBundleExt)
        
        let fullLocation = bundlePath
            .appendingPathComponent(dbFileName, isDirectory: false)
            .appendingPathExtension(dbFileExt)
        
        // Verify the bundle directory exists and database file is accessible
        if parentLocation.startAccessingSecurityScopedResource() {
            defer { parentLocation.stopAccessingSecurityScopedResource() }
            
            do {
                let parentContents = try FileManager.default.contentsOfDirectory(
                    at: parentLocation,
                    includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                let expectedBundleName = "\(folderName).\(folderBundleExt)"
                let bundleExists = parentContents.contains { $0.lastPathComponent == expectedBundleName }
                
                if bundleExists {
                    let fileExists = FileManager.default.fileExists(atPath: fullLocation.path)
                    if fileExists {
                        print("Custom database file found at: \(fullLocation.path)")
                        return fullLocation
                    } else {
                        print("Custom database file not found in bundle location")
                    }
                } else {
                    print("Bundle directory '\(expectedBundleName)' not found in parent directory")
                }
            } catch {
                print("Error checking bundle directory: \(error)")
            }
        } else {
            print("Cannot access parent directory to verify bundle directory")
        }
        
        // Fallback to default location
        print("Reverting to default database location")
        return defaultDatabaseBundleFullPath
    }
    
    static var saltyLibraryFullPath: URL {
        let path = customDatabaseBundleFullPath ?? defaultDatabaseBundleFullPath
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
    
    /// Saves bookmark for the parent directory only
    static func saveCustomLocationBookmarks(parentDirectory: URL) throws {
        // Save only the parent directory bookmark
        let parentBookmark = try parentDirectory.bookmarkData(options: [])
        UserDefaults.standard.set(parentBookmark, forKey: "databaseParentLocation")
        
        print("Saved bookmark for parent directory: \(parentDirectory.path)")
    }
    
    /// Clears the custom location bookmark
    static func clearCustomLocationBookmarks() {
        UserDefaults.standard.removeObject(forKey: "databaseParentLocation")
        print("Cleared custom location bookmark")
    }
    
    // MARK: - Security-Scoped Resource Management
    
    /// Checks if the custom database location is accessible and refreshes the bookmark if needed
    static func validateAndRefreshCustomDatabaseAccess() -> Bool {
        guard let customLocation = customSaltyLibraryDirectory else {
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
    
    /// Attempts to refresh the parent bookmark for the custom database location
    static func refreshCustomDatabaseBookmark() -> Bool {
        // Only refresh the parent bookmark since others are derived
        if let parentLocation = customSaltyLibraryDirectory {
            return refreshBookmark(for: "databaseParentLocation", at: parentLocation)
        }
        return false
    }
    
    /// Validates that the database file exists and is accessible
    static func validateDatabaseAccess() -> Bool {
        let databasePath = saltyLibraryFullPath
        
        // For custom locations, ensure we have proper access
        if customSaltyLibraryDirectory != nil {
            guard validateAndRefreshCustomDatabaseAccess() else {
                print("Failed to validate custom database access")
                return false
            }
        }
        
        // Check if the database file exists
        guard FileManager.default.fileExists(atPath: databasePath.path) else {
            print("Database file does not exist at: \(databasePath.path)")
            
            // Additional diagnostics for iOS/iCloud issues
            if customSaltyLibraryDirectory != nil {
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
        let isCustomLocation = customSaltyLibraryDirectory != nil
        diagnostics["isCustomLocation"] = isCustomLocation
        
        if isCustomLocation {
            diagnostics["customLocationPath"] = customSaltyLibraryDirectory?.path ?? "Unknown"
            diagnostics["bundleLocationPath"] = customDatabaseBundleFullPath?.path ?? "Unknown"
            diagnostics["imagesLocationPath"] = customImagesDirectory?.path ?? "Unknown"
            
            // Check parent bookmark status
            if let bookmarkData = UserDefaults.standard.data(forKey: "databaseParentLocation") {
                var wasStale = false
                if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) {
                    diagnostics["databaseParentLocation_resolved"] = true
                    diagnostics["databaseParentLocation_wasStale"] = wasStale
                    diagnostics["databaseParentLocation_path"] = resolvedURL.path
                    
                    // Test access to parent directory
                    if resolvedURL.startAccessingSecurityScopedResource() {
                        defer { resolvedURL.stopAccessingSecurityScopedResource() }
                        
                        do {
                            let contents = try FileManager.default.contentsOfDirectory(
                                at: resolvedURL,
                                includingPropertiesForKeys: [.nameKey],
                                options: [.skipsHiddenFiles]
                            )
                            diagnostics["databaseParentLocation_accessible"] = true
                            diagnostics["databaseParentLocation_contents"] = contents.map { $0.lastPathComponent }
                        } catch {
                            diagnostics["databaseParentLocation_accessible"] = false
                            diagnostics["databaseParentLocation_accessError"] = error.localizedDescription
                        }
                    } else {
                        diagnostics["databaseParentLocation_accessible"] = false
                        diagnostics["databaseParentLocation_accessError"] = "Failed to start accessing security-scoped resource"
                    }
                } else {
                    diagnostics["databaseParentLocation_resolved"] = false
                    diagnostics["databaseParentLocation_resolveError"] = "Unable to resolve bookmark data"
                }
            } else {
                diagnostics["databaseParentLocation_exists"] = false
            }
            
            // Test the actual database path that would be used
            if let parentLocation = customSaltyLibraryDirectory {
                let bundlePath = parentLocation
                    .appendingPathComponent(folderName, isDirectory: true)
                    .appendingPathExtension(folderBundleExt)
                
                let databasePath = bundlePath
                    .appendingPathComponent(dbFileName, isDirectory: false)
                    .appendingPathExtension(dbFileExt)
                
                diagnostics["expectedDatabasePath"] = databasePath.path
                diagnostics["expectedDatabaseExists"] = FileManager.default.fileExists(atPath: databasePath.path)
                
                // Test if we can access the database file
                if parentLocation.startAccessingSecurityScopedResource() {
                    defer { parentLocation.stopAccessingSecurityScopedResource() }
                    
                    if FileManager.default.fileExists(atPath: databasePath.path) {
                        do {
                            let attributes = try FileManager.default.attributesOfItem(atPath: databasePath.path)
                            diagnostics["expectedDatabaseAccessible"] = true
                            diagnostics["expectedDatabaseSize"] = attributes[.size] ?? 0
                        } catch {
                            diagnostics["expectedDatabaseAccessible"] = false
                            diagnostics["expectedDatabaseAccessError"] = error.localizedDescription
                        }
                    } else {
                        diagnostics["expectedDatabaseAccessible"] = false
                        diagnostics["expectedDatabaseAccessError"] = "File does not exist"
                    }
                } else {
                    diagnostics["expectedDatabaseAccessible"] = false
                    diagnostics["expectedDatabaseAccessError"] = "Cannot access security-scoped resource"
                }
            }
        }
        
        // Check database file (current path being used)
        let databasePath = saltyLibraryFullPath
        diagnostics["currentDatabasePath"] = databasePath.path
        diagnostics["currentDatabaseExists"] = FileManager.default.fileExists(atPath: databasePath.path)
        
        if FileManager.default.fileExists(atPath: databasePath.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: databasePath.path)
                diagnostics["currentDatabaseSize"] = attributes[.size] ?? 0
                diagnostics["currentDatabasePermissions"] = attributes[.posixPermissions] ?? 0
            } catch {
                diagnostics["currentDatabaseAccessError"] = error.localizedDescription
            }
        }
        
        // Check directory permissions for current path
        let directoryPath = databasePath.deletingLastPathComponent()
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directoryPath, includingPropertiesForKeys: [.nameKey])
            diagnostics["currentDirectoryAccessible"] = true
            diagnostics["currentDirectoryContentsCount"] = contents.count
            diagnostics["currentDirectoryContents"] = contents.map { $0.lastPathComponent }
        } catch {
            diagnostics["currentDirectoryAccessible"] = false
            diagnostics["currentDirectoryAccessError"] = error.localizedDescription
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
    
    /// Provides actionable guidance based on current diagnostic state
    static func getDatabaseTroubleshootingGuidance() -> String {
        let diagnostics = getDatabaseAccessDiagnostics()
        
        guard let isCustomLocation = diagnostics["isCustomLocation"] as? Bool, isCustomLocation else {
            return "Using default database location. No custom location configured."
        }
        
        var guidance = "Custom location configured. "
        
        // Check if bookmarks are resolving
        let parentResolved = diagnostics["databaseParentLocation_resolved"] as? Bool ?? false
        let bundleResolved = diagnostics["databaseBundleLocation_resolved"] as? Bool ?? false
        let imagesResolved = diagnostics["imagesLocation_resolved"] as? Bool ?? false
        
        if !parentResolved || !bundleResolved || !imagesResolved {
            guidance += "Some bookmarks are not resolving properly. Try resetting to default and re-selecting the location. "
        }
        
        // Check if expected database is accessible
        let expectedAccessible = diagnostics["expectedDatabaseAccessible"] as? Bool ?? false
        if !expectedAccessible {
            guidance += "Cannot access the database file in the custom location. "
            
            if let error = diagnostics["expectedDatabaseAccessError"] as? String {
                guidance += "Error: \(error). "
            }
            
            guidance += "The app may be falling back to the default location. "
        }
        
        // Check if current database is different from expected
        let currentPath = diagnostics["currentDatabasePath"] as? String ?? ""
        let expectedPath = diagnostics["expectedDatabasePath"] as? String ?? ""
        
        if currentPath != expectedPath && !expectedPath.isEmpty {
            guidance += "Using fallback database location instead of custom location. "
        }
        
        if guidance.hasSuffix(". ") {
            guidance = String(guidance.dropLast(2))
        }
        
        return guidance
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
