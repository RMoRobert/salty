//
//  FileHelper.swift
//  Salty
//
//  Created by Robert on 5/30/23.
//

import Foundation
import OSLog
import SaltyCore

private let fileLogger = Logger(subsystem: "Salty", category: "FileAccess")

// MARK: - Size-limited file reads (import hardening)

/// Upper bounds on files pulled in through the import flows, so an extra-large  file
/// can't exhaust memory. Should be egenerous enough for most real recipe photos, scans, or cookbook PDFs.
enum ImportFileLimits {
    static let maxImageBytes = 100 * 1024 * 1024   // 100 MB
    static let maxPDFBytes = 500 * 1024 * 1024    // 500 MB

    /// Cap on a single recipe file. Generous because formats that embed photos as base64 (Crouton's
    /// .crumb, a .saltyRecipe carrying an image) are several MB per recipe before anything is wrong.
    static let maxRecipeFileBytes = 100 * 1024 * 1024   // 100 MB

    /// Cap on image bytes accepted from the sync server, so a hostile/misbehaving server can't make a
    /// sync balloon memory or disk. Deliberately larger than maxImageBytes: a server image can
    /// legitimately exceed the local import cap because uploads are converted before sending
    /// (HEIC → PNG can inflate several-fold) and other clients may apply different limits.
    static let maxSyncImageDownloadBytes = 250 * 1024 * 1024   // 250 MB
}

extension Data {
    /// Reads `url` only when the file is within `maxBytes`, returning nil (and logging) if it's too large
    /// or unreadable, so callers bail gracefully instead of loading a huge file entirely into memory.
    static func contents(of url: URL, maxBytes: Int) -> Data? {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes {
            fileLogger.error("Refusing to read oversized import file: \(size) bytes exceeds \(maxBytes)-byte limit")
            return nil
        }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            fileLogger.error("Failed to read import file: \(error.localizedDescription)")
            return nil
        }
    }
}

extension FileManager {

    // MARK: - Constants

    static let folderName = "SaltyRecipeLibrary"
    static let folderBundleExt = "saltyRecipeLibrary"
    static let dbFileName = "saltyRecipeDB"
    static let dbFileExt = "sqlite"
    static let backupFolderName = "Backup"
    static let saltyImageFolderName = "recipeImages"

    // Use different UserDefaults keys (and therefore default DB locations) for dev vs prod.
    // Less necessary now that debug builds use different bundle IDs, but still handy for Xcode runs.
    #if DEBUG
    static let userDefaultsDatabaseParentLocationKey = "databaseParentLocation-DEV"
    #else
    static let userDefaultsDatabaseParentLocationKey = "databaseParentLocation"
    #endif

    // MARK: - Security-scoped bookmark options (platform-specific)
    //
    // On sandboxed macOS, durable access to a user-selected folder REQUIRES creating and
    // resolving the bookmark with `.withSecurityScope` (plus the bookmarks.app-scope and
    // files.user-selected.read-write entitlements). On iOS that option does not exist; the
    // document picker grants access and a plain bookmark + start/stopAccessing is used instead.

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    // MARK: - Default (in-container) location

    static var userDocumentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Default library bundle directory inside the app's Documents directory.
    static var defaultSaltyLibraryDirectory: URL {
        userDocumentsDirectory
            .appendingPathComponent("Salty Recipe Library", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathExtension(folderBundleExt)
    }

    /// Default database file path (used for display / when no custom location is set).
    static var defaultDatabaseFileFullPath: URL {
        defaultSaltyLibraryDirectory
            .appendingPathComponent(dbFileName, isDirectory: false)
            .appendingPathExtension(dbFileExt)
    }

    // MARK: - Custom location resolution (single source of truth, persistent scope)
    //
    // The resolved custom-parent URL and its security-scoped access are cached for the
    // lifetime of the process. We start accessing the resource ONCE and never stop until
    // the location is cleared/changed, so the long-lived SQLite connection (and its
    // -wal/-shm files) and the image folder stay accessible the whole time the app runs.

    private static let accessLock = NSLock()
    nonisolated(unsafe) private static var cachedCustomParent: URL?
    nonisolated(unsafe) private static var hasResolvedCustomParent = false
    nonisolated(unsafe) private static var isHoldingAccess = false

    /// Resolves (once) the user's custom database parent folder, beginning and holding
    /// security-scoped access. Returns nil when no custom location is configured or it
    /// cannot be resolved.
    @discardableResult
    static func resolveCustomParentLocation() -> URL? {
        accessLock.lock()
        defer { accessLock.unlock() }

        if hasResolvedCustomParent {
            return cachedCustomParent
        }

        guard let bookmarkData = UserDefaults.standard.data(forKey: userDefaultsDatabaseParentLocationKey) else {
            hasResolvedCustomParent = true
            return nil
        }

        var wasStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &wasStale
        ) else {
            fileLogger.error("Unable to resolve custom database bookmark for key \(userDefaultsDatabaseParentLocationKey)")
            hasResolvedCustomParent = true
            return nil
        }

        // Begin (and hold) security-scoped access for the lifetime of the app / until changed.
        let didAccess = url.startAccessingSecurityScopedResource()
        if !didAccess {
            // On macOS this usually means a missing entitlement or an unusable/stale bookmark.
            fileLogger.error("startAccessingSecurityScopedResource() failed for custom database location: \(url.path)")
        }

        // Refresh a stale bookmark now that we (hopefully) hold access.
        if wasStale {
            do {
                let refreshed = try url.bookmarkData(
                    options: bookmarkCreationOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(refreshed, forKey: userDefaultsDatabaseParentLocationKey)
                fileLogger.info("Refreshed stale custom database bookmark")
            } catch {
                fileLogger.error("Failed to refresh stale bookmark: \(error.localizedDescription)")
            }
        }

        cachedCustomParent = url
        isHoldingAccess = didAccess
        hasResolvedCustomParent = true
        return url
    }

    /// The user's custom database parent folder, or nil if using the default location.
    static var customSaltyLibraryDirectory: URL? {
        resolveCustomParentLocation()
    }

    /// Clears the cached resolution and releases any held security-scoped access so the
    /// next resolution re-reads UserDefaults.
    private static func resetCustomLocationCache() {
        accessLock.lock()
        defer { accessLock.unlock() }
        if isHoldingAccess, let cached = cachedCustomParent {
            cached.stopAccessingSecurityScopedResource()
        }
        cachedCustomParent = nil
        isHoldingAccess = false
        hasResolvedCustomParent = false
    }

    // MARK: - Derived paths (all computed from a single source of truth)

    /// The active library bundle directory (custom if configured, otherwise default).
    static var saltyLibraryDirectory: URL {
        if let custom = customSaltyLibraryDirectory {
            return custom
                .appendingPathComponent(folderName, isDirectory: true)
                .appendingPathExtension(folderBundleExt)
        }
        return defaultSaltyLibraryDirectory
    }

    /// The active database file path, ensuring its containing directory exists.
    static var saltyLibraryFullPath: URL {
        let dir = saltyLibraryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir
            .appendingPathComponent(dbFileName, isDirectory: false)
            .appendingPathExtension(dbFileExt)
        fileLogger.info("Database path: \(path.path)")
        return path
    }

    /// The active image folder (lives inside the library bundle).
    static var saltyImageFolderUrl: URL {
        saltyLibraryDirectory.appendingPathComponent(saltyImageFolderName, isDirectory: true)
    }

    /// Backups live alongside the library bundle (in its parent directory).
    static var backupDirectory: URL {
        saltyLibraryDirectory
            .deletingLastPathComponent()
            .appendingPathComponent(backupFolderName, isDirectory: true)
    }

    // MARK: - Lifecycle: opening / changing / clearing the custom location

    /// Saves a security-scoped bookmark for the user-selected parent folder.
    ///
    /// The caller must already hold access to `parentDirectory` (e.g. the URL just came
    /// from a file picker, or `startAccessingSecurityScopedResource()` returned true) so
    /// the security-scoped bookmark can be created.
    static func saveCustomLocationBookmarks(parentDirectory: URL) throws {
        let bookmark = try parentDirectory.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: userDefaultsDatabaseParentLocationKey)
        // Drop any cached/held access so the new location is picked up on next resolution.
        resetCustomLocationCache()
        fileLogger.info("Saved security-scoped bookmark for custom database location: \(parentDirectory.path)")
    }

    /// Clears the custom location, reverting to the default (in-container) location.
    static func clearCustomLocationBookmarks() {
        UserDefaults.standard.removeObject(forKey: userDefaultsDatabaseParentLocationKey)
        resetCustomLocationCache()
        fileLogger.info("Cleared custom database location; reverting to default")
    }

    /// Begins (and holds) access to the active database location. Safe to call repeatedly.
    /// For the default in-container location no security scope is needed.
    @discardableResult
    static func beginAccessingDatabaseLocation() -> Bool {
        guard UserDefaults.standard.data(forKey: userDefaultsDatabaseParentLocationKey) != nil else {
            return true // default container location is always accessible
        }
        return resolveCustomParentLocation() != nil
    }

    /// Resolves the location (refreshing a stale bookmark if needed). Retained for the
    /// app-launch call site; now correctly keyed and backed by `resolveCustomParentLocation()`.
    static func refreshBookmarksIfNeeded() {
        _ = resolveCustomParentLocation()
    }

    /// Forces a fresh resolution of the custom location bookmark.
    @discardableResult
    static func refreshCustomDatabaseBookmark() -> Bool {
        resetCustomLocationCache()
        return resolveCustomParentLocation() != nil
    }

    /// Validates that the active database location is accessible (directory readable/creatable). A
    /// missing database file is *not* a failure -- it just means this location hasn't been initialized yet.
    static func validateDatabaseAccess() -> Bool {
        if UserDefaults.standard.data(forKey: userDefaultsDatabaseParentLocationKey) != nil {
            guard resolveCustomParentLocation() != nil, isHoldingAccess else {
                fileLogger.error("Custom database location could not be accessed")
                return false
            }
        }

        let dir = saltyLibraryDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return true
        } catch {
            fileLogger.error("Cannot access or create library directory at \(dir.path): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Diagnostics (shown in Settings → Database)

    static func getDatabaseAccessDiagnostics() -> [String: Any] {
        var d: [String: Any] = [:]

        let hasCustomBookmark = UserDefaults.standard.data(forKey: userDefaultsDatabaseParentLocationKey) != nil
        d["isCustomLocation"] = hasCustomBookmark

        if hasCustomBookmark {
            if let parent = resolveCustomParentLocation() {
                d["customParentResolved"] = true
                d["customParentPath"] = parent.path
                d["holdingSecurityScopedAccess"] = isHoldingAccess
            } else {
                d["customParentResolved"] = false
            }
        }

        let dir = saltyLibraryDirectory
        d["libraryDirectory"] = dir.path

        let dbPath = dir
            .appendingPathComponent(dbFileName, isDirectory: false)
            .appendingPathExtension(dbFileExt)
        d["databasePath"] = dbPath.path
        d["databaseExists"] = FileManager.default.fileExists(atPath: dbPath.path)

        if FileManager.default.fileExists(atPath: dbPath.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath.path) {
            d["databaseSizeBytes"] = attrs[.size] ?? 0
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            d["libraryDirectoryAccessible"] = true
            d["libraryDirectoryContents"] = contents
        } catch {
            d["libraryDirectoryAccessible"] = false
            d["libraryDirectoryError"] = error.localizedDescription
        }

        return d
    }

    /// Plain-language guidance based on the current diagnostic state.
    static func getDatabaseTroubleshootingGuidance() -> String {
        let d = getDatabaseAccessDiagnostics()

        guard (d["isCustomLocation"] as? Bool) == true else {
            return "Using the default database location inside the app's container. No custom location is configured."
        }

        var parts: [String] = ["A custom database location is configured."]

        if (d["customParentResolved"] as? Bool) != true {
            parts.append("The saved location could not be resolved. Re-select the folder with “Select Custom Database Location…”, or reset to the default location.")
        } else if (d["holdingSecurityScopedAccess"] as? Bool) != true {
            parts.append("The location resolved but the app could not obtain access to it. This usually means a missing sandbox entitlement or a stale bookmark. Try re-selecting the folder.")
        }

        if (d["databaseExists"] as? Bool) != true {
            parts.append("No database file has been created at this location yet.")
        }

        if (d["libraryDirectoryAccessible"] as? Bool) != true {
            parts.append("The library directory is not readable.")
        }

        return parts.joined(separator: " ")
    }
}
