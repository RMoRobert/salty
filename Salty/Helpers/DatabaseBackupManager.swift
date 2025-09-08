//
//  DatabaseBackupManager.swift
//  Salty
//
//  Created by Robert on 7/18/25.
//

import Foundation
import SharingGRDB
import OSLog

public final class DatabaseBackupManager {
    @Dependency(\.defaultDatabase) private var database
    private let logger = Logger(subsystem: "Salty", category: "DatabaseBackup")
    
    // MARK: - Constants
    private static let backupFileExtension = "zip"
    private static let backupRecencyThreshold: TimeInterval = 36 * 60 * 60 // 36 hours
    private static let maxBackupsToKeep = 3
    
    // MARK: - Backup Directory
    private var backupDirectory: URL {
        return FileManager.backupDirectory
    }
    
    // MARK: - Public Methods
    
    /// Creates a backup if one doesn't exist from the last few hours
    public func createBackupIfNeeded() {
        Task {
            await createBackupIfNeededAsync()
        }
    }
    
    /// Creates a backup immediately, regardless of when the last one was created
    public func createBackupNow() {
        Task {
            await createBackupAsync()
        }
    }
    
    // MARK: - Private Methods
    
    private func createBackupIfNeededAsync() async {
        // Check if we need a backup
        guard await shouldCreateBackup() else {
            logger.info("Recent backup exists, skipping backup creation")
            return
        }
        
        await createBackupAsync()
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
    
    private func createBackupAsync() async {
        do {
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
            
        } catch {
            logger.error("Failed to create database backup: \(error)")
        }
    }
    
    private func createBackupZip(at backupURL: URL) async throws {
        let zipService = ZipService()
        zipService.shouldOverwriteIfNecessary = true
        
        // Get the entire Salty library directory (the *.saltyRecipeLibrary folder)
        let saltyLibraryDirectory = FileManager.saltyLibraryDirectory
        
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
        
        // Copy the entire Salty library directory structure
        let libraryName = saltyLibraryDirectory.lastPathComponent
        let backupLibraryDir = tempBackupDirectory.appendingPathComponent(libraryName)
        
        try FileManager.default.copyItem(at: saltyLibraryDirectory, to: backupLibraryDir)
        logger.debug("Copied entire Salty library directory: \(libraryName)")
        
        // Create the ZIP file
        let _ = try zipService.createZip(zipFinalURL: backupURL, fromDirectory: tempBackupDirectory)
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
            
            // Remove old backups if we have more than the maximum
            if backupFiles.count > Self.maxBackupsToKeep {
                let filesToDelete = Array(backupFiles.dropFirst(Self.maxBackupsToKeep))
                for fileURL in filesToDelete {
                    try FileManager.default.removeItem(at: fileURL)
                    logger.info("Deleted old backup: \(fileURL.lastPathComponent)")
                }
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

