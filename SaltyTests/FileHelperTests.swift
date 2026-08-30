//
//  FileHelperTests.swift
//  SaltyTests
//
//  Deterministic tests for the default (in-container) path derivation and the
//  UserDefaults key wiring. These do not exercise security-scoped custom locations,
//  which require a real user-selected folder and cannot be unit tested in isolation.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct FileHelperTests {

    @Test func bundleAndFileConstantsAreStable() {
        // These strings define on-disk layout; changing them silently would orphan
        // every existing user's library, so pin them.
        #expect(FileManager.folderName == "SaltyRecipeLibrary")
        #expect(FileManager.folderBundleExt == "saltyRecipeLibrary")
        #expect(FileManager.dbFileName == "saltyRecipeDB")
        #expect(FileManager.dbFileExt == "sqlite")
        #expect(FileManager.saltyImageFolderName == "recipeImages")
    }

    @Test func defaultLibraryDirectoryIsWellFormed() {
        let dir = FileManager.defaultSaltyLibraryDirectory
        #expect(dir.pathExtension == FileManager.folderBundleExt)
        #expect(dir.deletingPathExtension().lastPathComponent == FileManager.folderName)
        // Lives under the Documents directory.
        #expect(dir.path.contains("Salty Recipe Library"))
    }

    @Test func defaultDatabasePathIsInsideLibraryDirectory() {
        let dbPath = FileManager.defaultDatabaseFileFullPath
        #expect(dbPath.lastPathComponent == "saltyRecipeDB.sqlite")
        #expect(dbPath.deletingLastPathComponent() == FileManager.defaultSaltyLibraryDirectory)
    }

    @Test func imageAndBackupFoldersDeriveFromLibraryDirectory() {
        // When no custom location is configured, derived folders hang off the default library dir.
        if FileManager.customSaltyLibraryDirectory == nil {
            #expect(FileManager.saltyImageFolderUrl.deletingLastPathComponent() == FileManager.saltyLibraryDirectory)
            #expect(FileManager.saltyImageFolderUrl.lastPathComponent == FileManager.saltyImageFolderName)
            #expect(FileManager.backupDirectory.lastPathComponent == FileManager.backupFolderName)
            #expect(FileManager.saltyLibraryDirectory == FileManager.defaultSaltyLibraryDirectory)
        }
    }

    @Test func userDefaultsKeyMatchesDebugBuildConfiguration() {
        // The tests build in Debug, so the dev-specific key must be in use. This pins the
        // fix for the historical wrong-key bug (refresh logic read a different key than it wrote).
        #expect(FileManager.userDefaultsDatabaseParentLocationKey == "databaseParentLocation-DEV")
    }

    @Test func diagnosticsReportDefaultLocationWhenNoCustomBookmark() {
        // Only meaningful when the test host has no custom location configured.
        guard FileManager.customSaltyLibraryDirectory == nil else { return }

        let diagnostics = FileManager.getDatabaseAccessDiagnostics()
        #expect(diagnostics["isCustomLocation"] as? Bool == false)
        #expect(diagnostics["libraryDirectory"] as? String == FileManager.defaultSaltyLibraryDirectory.path)

        let guidance = FileManager.getDatabaseTroubleshootingGuidance()
        #expect(guidance.contains("default database location"))
    }
}
