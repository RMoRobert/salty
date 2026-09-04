//
//  DatabaseBackupManager.swift
//  Salty
//
//  Created by Robert on 7/18/25.
//

import Foundation
import SQLiteData
import GRDB
import OSLog

// Safe to share across tasks: the only stored state is an immutable Logger and the injected
// database dependency (set once, read-only). The backup methods run off the main actor (via the
// `Task {}` triggers below) and use only local state, so there is no concurrent mutable state.
//
// ⚠️ `@unchecked` means the compiler does NOT verify this. If you add mutable stored state, the
// race will compile silently. Guard with a lock/actor, isolate to an actor or @MainActor, or
// re-justify this annotation.
public final class DatabaseBackupManager: @unchecked Sendable {
    @Dependency(\.defaultDatabase) private var database
    private let logger = Logger(subsystem: "Salty", category: "DatabaseBackup")
    
    // MARK: - Constants
    private static let backupFileExtension = "zip"
    private static let backupRecencyThreshold: TimeInterval = 36 * 60 * 60 // 36 hours

    // MARK: - Retention policy

    /// How many of the newest backups are always kept, whatever their spacing.
    ///
    /// Bad data is usually noticed a few launches after it happened, and each launch past the recency
    /// threshold takes a new backup *of the bad state*. Keeping several recent ones means the last
    /// good backup survives those launches instead of being the one deleted to make room.
    static let recentBackupsToKeep = 2

    /// Ages (measured from the newest backup) that divide the older backups into bands. One backup
    /// survives per band; see `retainedBackupIndices(ages:)` for which.
    static let retentionBandBoundaries: [TimeInterval] = [
        5 * 24 * 60 * 60,   // 5 days
        20 * 24 * 60 * 60,  // 20 days
    ]

    /// Decides which backups to keep. `ages` are seconds older than the newest backup, sorted
    /// ascending (so `ages[0] == 0` is the newest); the result is the indices to keep.
    ///
    /// The rules, and why each one is there:
    /// - The newest `recentBackupsToKeep` are always kept.
    /// - Inside each band except the last, the *oldest* backup is kept. That backup is the one that
    ///   will cross into the next band as time passes, so bands further out actually get populated.
    ///   (The previous policy kept the *newest* candidate, which, with a backup every ~36 hours,
    ///   was deleted before it could ever become 5 days old; the older tiers never filled.)
    /// - In the last band the *newest* backup is kept, so that band rolls forward and the very first
    ///   backup ever taken doesn't live forever.
    ///
    /// Pure and static so it can be tested without touching the filesystem.
    static func retainedBackupIndices(ages: [TimeInterval]) -> Set<Int> {
        guard !ages.isEmpty else { return [] }
        var keep = Set(0..<min(recentBackupsToKeep, ages.count))

        let lowerBounds = [0] + retentionBandBoundaries
        for (bandIndex, lower) in lowerBounds.enumerated() {
            let isLastBand = bandIndex == lowerBounds.count - 1
            let upper = isLastBand ? TimeInterval.infinity : lowerBounds[bandIndex + 1]
            let members = ages.indices.filter { ages[$0] >= lower && ages[$0] < upper }
            guard !members.isEmpty else { continue }
            // Ascending ages: the newest member has the smallest index, the oldest the largest.
            keep.insert(isLastBand ? members.min()! : members.max()!)
        }
        return keep
    }

    // MARK: - Backup Directory
    private var backupDirectory: URL {
        return FileManager.backupDirectory
    }

    // MARK: - Public Methods

    /// Creates a backup if one doesn't exist from the last few hours. Fire-and-forget: meant for app
    /// launch, where nobody is waiting on the result and a failure is only worth a log line.
    public func createBackupIfNeeded() {
        Task {
            await createBackupIfNeededAsync()
        }
    }

    /// Creates a backup immediately, regardless of when the last one was created, and returns the
    /// file it wrote. Throws when the backup could not be made, so a caller reporting to the user
    /// can say what actually happened.
    @discardableResult
    public func createBackupNow() async throws -> URL {
        try await createBackup()
    }

    // MARK: - Private Methods

    private func createBackupIfNeededAsync() async {
        // Check if we need a backup
        guard await shouldCreateBackup() else {
            logger.info("Recent backup exists, skipping backup creation")
            return
        }

        do {
            try await createBackup()
        } catch {
            logger.error("Failed to create database backup: \(error)")
        }
    }
    
    private func shouldCreateBackup() async -> Bool {
        do {
            // Ensure backup directory exists
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: nil)
            
            // Get all backup files
            let backupFiles = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == Self.backupFileExtension }
                .sorted { file1, file2 in
                    let date1 = try file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return date1 > date2
                }
            
            // If no backups exist, we should create one
            guard let mostRecentBackup = backupFiles.first else {
                logger.info("No existing backups found, will create new backup")
                return true
            }
            
            // Check if the most recent backup is older than our desired interval
            let mostRecentDate = try mostRecentBackup.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
            let timeSinceLastBackup = Date().timeIntervalSince(mostRecentDate)
            
            let shouldCreate = timeSinceLastBackup > Self.backupRecencyThreshold
            logger.info("Most recent backup is \(timeSinceLastBackup / 3600) hours old; should create new backup = \(shouldCreate)")
            
            return shouldCreate
            
        } catch {
            logger.error("Error checking backup status: \(error)")
            // If we can't check, err on the side of creating a backup
            return true
        }
    }
    
    @discardableResult
    private func createBackup() async throws -> URL {
        logger.info("Starting database backup...")

        // Create backup directory if it doesn't exist
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: nil)

        // Generate backup filename with timestamp
        let timestamp = Date().formatted(.iso8601
            .year()
            .month()
            .day()
            .dateSeparator(.dash)
            .time(includingFractionalSeconds: false)
            .timeSeparator(.omitted)
        )
        let backupFilename = "salty-backup-\(timestamp).\(Self.backupFileExtension)"
        let backupURL = backupDirectory.appendingPathComponent(backupFilename)

        // Create the backup
        try await createBackupZip(at: backupURL)

        // Clean up old backups
        await cleanupOldBackups()

        logger.info("Database backup completed successfully: \(backupURL.lastPathComponent)")
        return backupURL
    }
    
    private func createBackupZip(at backupURL: URL) async throws {
        let zipService = ZipService()
        zipService.shouldOverwriteIfNecessary = true

        // Handle security-scoped resources for custom database locations
        var didStartAccessing = false
        var parentDirectory: URL?
        if let customLocation = FileManager.customSaltyLibraryDirectory {
            parentDirectory = customLocation
            didStartAccessing = customLocation.startAccessingSecurityScopedResource()
            if !didStartAccessing {
                logger.error("Failed to start accessing security-scoped resource for backup")
                throw NSError(domain: "DatabaseBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to access custom database location"])
            }
        }
        defer {
            if didStartAccessing, let parent = parentDirectory {
                parent.stopAccessingSecurityScopedResource()
            }
        }

        // Create a temporary directory to organize our backup contents
        let tempBackupDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaltyBackup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBackupDirectory, withIntermediateDirectories: true, attributes: nil)
        defer {
            // Clean up temporary directory
            try? FileManager.default.removeItem(at: tempBackupDirectory)
        }

        // Stage the backup mirroring the library bundle layout so a restore is drop-in.
        let libraryName = FileManager.saltyLibraryDirectory.lastPathComponent
        let backupLibraryDir = tempBackupDirectory.appendingPathComponent(libraryName, isDirectory: true)
        try FileManager.default.createDirectory(at: backupLibraryDir, withIntermediateDirectories: true, attributes: nil)

        // 1) Write a CONSISTENT database snapshot via SQLite's online backup API. A raw file
        //    copy of a live WAL database can capture a torn snapshot (committed data may still
        //    live in the -wal file mid-checkpoint); the online backup copies a coherent state.
        let snapshotURL = backupLibraryDir
            .appendingPathComponent(FileManager.dbFileName, isDirectory: false)
            .appendingPathExtension(FileManager.dbFileExt)
        try writeConsistentDatabaseSnapshot(to: snapshotURL)
        logger.debug("Wrote consistent database snapshot for backup")

        // 2) Copy the external image files referenced by the database, if present.
        let imagesSource = FileManager.saltyImageFolderUrl
        if FileManager.default.fileExists(atPath: imagesSource.path) {
            let imagesDest = backupLibraryDir.appendingPathComponent(FileManager.saltyImageFolderName, isDirectory: true)
            try FileManager.default.copyItem(at: imagesSource, to: imagesDest)
            logger.debug("Copied recipe images into backup")
        }

        // 3) Zip the staged library bundle.
        let _ = try zipService.createZip(zipFinalURL: backupURL, fromDirectory: tempBackupDirectory)
    }

    /// Writes a consistent, self-contained snapshot of the live database to `destinationURL`
    /// using SQLite's online backup API. The destination is a fresh `DatabaseQueue`
    /// (rollback-journal mode), so the result is a single `.sqlite` file with no `-wal`/`-shm`
    /// sidecars -- safe to copy, zip, or open directly.
    func writeConsistentDatabaseSnapshot(to destinationURL: URL) throws {
        // Remove any pre-existing file so the backup target starts empty.
        try? FileManager.default.removeItem(at: destinationURL)

        let snapshot = try DatabaseQueue(path: destinationURL.path)
        try database.backup(to: snapshot)
        try snapshot.close()
    }
    
    private func cleanupOldBackups() async {
        do {
            let backupFiles = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == Self.backupFileExtension }
                .sorted { file1, file2 in
                    let date1 = try file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return date1 > date2
                }

            // Nothing to do if 0 or 1 backups
            guard backupFiles.count > 1 else { return }

            // Build a list of (url, date) for convenience
            let backupsWithDates: [(url: URL, date: Date)] = try backupFiles.map { url in
                let date = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return (url, date)
            }

            let newestDate = backupsWithDates[0].date
            let ages = backupsWithDates.map { newestDate.timeIntervalSince($0.date) }
            let keep = Self.retainedBackupIndices(ages: ages)

            // Delete any backups not in the keep set
            for (index, backup) in backupsWithDates.enumerated() where !keep.contains(index) {
                try FileManager.default.removeItem(at: backup.url)
                logger.info("Deleted old backup: \(backup.url.lastPathComponent)")
            }
        } catch {
            logger.error("Error cleaning up old backups: \(error)")
        }
    }
    
    // MARK: - Utility Methods
    
    /// Gets the list of available backups
    public func getAvailableBackups() -> [URL] {
        do {
            let backupFiles = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == Self.backupFileExtension }
                .sorted { file1, file2 in
                    let date1 = try file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return date1 > date2
                }
            return backupFiles
        } catch {
            logger.error("Error getting available backups: \(error)")
            return []
        }
    }
    
    /// Gets the backup directory URL
    public func getBackupDirectory() -> URL {
        return backupDirectory
    }
    
    /// Gets the number of available backups
    public func getBackupCount() -> Int {
        return getAvailableBackups().count
    }
}

