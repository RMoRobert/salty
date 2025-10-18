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
    // Extra sure to ues different database locations by default for prod and dev; probably not as
    // necessary any more since debug builds have different bundle IDs, but may still be helpful.
    // (This is mostly for Xcode builds; does NOT include TestFlight, which is similar to prod.)
    #if DEBUG
    static let userDefaultsDatabaseParentLocationKey = "databaseParentLocation-DEV"
    #else
    static let userDefaultsDatabaseParentLocationKey = "databaseParentLocation"
    #endif
    
    static let userDocumentsDirectory = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    static let defaultSaltyLibraryDirectory = FileManager.userDocumentsDirectory()
        .appendingPathComponent("Salty Recipe Library", isDirectory: true)
        .appendingPathComponent(folderName, isDirectory: true)
        .appendingPathExtension(folderBundleExt)
    
    // MARK: - Custom Location Access (Single Parent Bookmark)
    
    
    // Legacy support - will be removed
    static var customSaltyLibraryDirectory: URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: userDefaultsDatabaseParentLocationKey) else {
            return nil
        }
        var wasStale = false
        guard let parentLocation = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) else {
            print("Unable to resolve \(userDefaultsDatabaseParentLocationKey)")
            return nil
        }
        if wasStale {
            let _ = refreshBookmark(for: userDefaultsDatabaseParentLocationKey, at: parentLocation)
        }
        return parentLocation
    }
    
    static let saltyLibraryDirectory: URL = {
        // If user has a custom database location, construct the bundle path
        if let customLocation = customSaltyLibraryDirectory {
            return customLocation
                .appendingPathComponent(folderName, isDirectory: true)
                .appendingPathExtension(folderBundleExt)
        } else {
            // Otherwise, use the default library directory
            return defaultSaltyLibraryDirectory
        }
    }()

    static var defaultDatabaseFileFullPath: URL {
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

    static var customDatabaseFileFullPath: URL? {
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
        return defaultDatabaseFileFullPath
    }
    
    static var saltyLibraryFullPath: URL {
        let path = customDatabaseFileFullPath ?? defaultDatabaseFileFullPath
        print("Opening database at path: \(path)")
        return path
    }
    
    /// Returns the appropriate backup directory URL based on whether a custom location is set
    static var backupDirectory: URL {
        // Put backups in the parent directory of the library directory
        return saltyLibraryDirectory.deletingLastPathComponent().appendingPathComponent(backupFolderName, isDirectory: true)
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
    
    /// Saves bookmark for the parent directory only (have tried saving bundle directory and image directory separately to see if helps with iOS issues but has not so far)
    static func saveCustomLocationBookmarks(parentDirectory: URL) throws {
        // Save the parent directory bookmark
        let parentBookmark = try parentDirectory.bookmarkData(options: [])
        UserDefaults.standard.set(parentBookmark, forKey: userDefaultsDatabaseParentLocationKey)
        print("Saved bookmark for parent directory: \(parentDirectory.path)")
    }
    
    /// Clears the custom location bookmark
    static func clearCustomLocationBookmarks() {
        UserDefaults.standard.removeObject(forKey: userDefaultsDatabaseParentLocationKey)
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
            return refreshBookmark(for: userDefaultsDatabaseParentLocationKey, at: parentLocation)
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
            diagnostics["bundleLocationPath"] = customDatabaseFileFullPath?.path ?? "Unknown"
            diagnostics["imagesLocationPath"] = saltyImageFolderUrl.path
            
            // Check parent bookmark status
            if let bookmarkData = UserDefaults.standard.data(forKey: userDefaultsDatabaseParentLocationKey) {
                var wasStale = false
                if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &wasStale) {
                    diagnostics["\(userDefaultsDatabaseParentLocationKey)_resolved"] = true
                    diagnostics["\(userDefaultsDatabaseParentLocationKey)_wasStale"] = wasStale
                    diagnostics["\(userDefaultsDatabaseParentLocationKey)_path"] = resolvedURL.path
                    
                    // Test access to parent directory
                    if resolvedURL.startAccessingSecurityScopedResource() {
                        defer { resolvedURL.stopAccessingSecurityScopedResource() }
                        
                        do {
                            let contents = try FileManager.default.contentsOfDirectory(
                                at: resolvedURL,
                                includingPropertiesForKeys: [.nameKey],
                                options: [.skipsHiddenFiles]
                            )
                            diagnostics["\(userDefaultsDatabaseParentLocationKey)_accessible"] = true
                            diagnostics["\(userDefaultsDatabaseParentLocationKey)contents"] = contents.map { $0.lastPathComponent }
                        } catch {
                            diagnostics["\(userDefaultsDatabaseParentLocationKey)_accessible"] = false
                            diagnostics["\(userDefaultsDatabaseParentLocationKey)_accessError"] = error.localizedDescription
                        }
                    } else {
                        diagnostics["\(userDefaultsDatabaseParentLocationKey)_accessible"] = false
                        diagnostics["\(userDefaultsDatabaseParentLocationKey)_accessError"] = "Failed to start accessing security-scoped resource"
                    }
                } else {
                    diagnostics["\(userDefaultsDatabaseParentLocationKey)_resolved"] = false
                    diagnostics["\(userDefaultsDatabaseParentLocationKey)_resolveError"] = "Unable to resolve bookmark data"
                }
            } else {
                diagnostics["\(userDefaultsDatabaseParentLocationKey)_exists"] = false
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
        let parentResolved = diagnostics["\(userDefaultsDatabaseParentLocationKey)_resolved"] as? Bool ?? false
        let bundleResolved = diagnostics["databaseBundleLocation_resolved"] as? Bool ?? false
        let imagesResolved = diagnostics["imagesLocation_resolved"] as? Bool ?? false
        
        if !parentResolved || !bundleResolved || !imagesResolved {
            guidance += "Some file/folder location \"bookmarks\" are not resolving properly. Try re-selecting the location if custom or resetting to the default location. "
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
