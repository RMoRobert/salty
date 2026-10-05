//
//  CheckLibraryTests.swift
//  SaltyTests
//
//  `checkLibrary(atPath:)`, the off-main check the open-database screen runs on a newly chosen folder.
//

import Testing
import Foundation
import GRDB
@testable import Salty

struct CheckLibraryTests {
    @Test func anEmptyFolderGetsAMigratedLibraryAndIsLeftClosed() async throws {
        let folder = URL.temporaryDirectory.appending(component: "check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(component: "saltyRecipeDB.sqlite").path()

        try await Task.detached { try checkLibrary(atPath: path) }.value

        // A second open succeeds and finds the schema, so the check left a usable, unlocked file.
        let queue = try DatabaseQueue(path: path)
        let hasRecipes = try await queue.read { db in try db.tableExists("recipe") }
        #expect(hasRecipes)
        // Running it again over an existing library is a no-op migration, not a failure.
        try checkLibrary(atPath: path)
    }

    @Test func aPathThatCantHoldALibraryThrows() {
        #expect(throws: (any Error).self) {
            try checkLibrary(atPath: "/nonexistent-\(UUID().uuidString)/saltyRecipeDB.sqlite")
        }
    }
}
