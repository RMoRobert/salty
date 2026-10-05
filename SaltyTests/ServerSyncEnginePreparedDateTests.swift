//
//  ServerSyncEnginePreparedDateTests.swift
//  SaltyTests
//
//  The "last made on" channel, keyed on `lastModifiedPreparedDate` because marking a recipe made
//  deliberately leaves `lastModifiedDate` alone: a newer local stamp piggybacks a whole-row upload
//  the body pass would never make; a newer server stamp is written with a targeted UPDATE that leaves
//  `lastModifiedDate` byte-identical; a nil stamp never wins.
//

import Testing
import Foundation
import GRDB
@testable import Salty
import SaltyCore

@Suite(.serialized)
struct ServerSyncEnginePreparedDateTests {
    private typealias Stub = SyncEngineStubURLProtocol
    private let clock = SyncTestClock.self

    private func routes(manifest: [ManifestEntry]) throws -> [Stub.Route] {
        [
            .init("HEAD", "/api/recipes/r1", body: ""),
            .init("GET", "/api/recipes/sync/manifest", body: try wireJSON(manifest)),
        ] + syncBaseRoutes(lastSync: SyncTestClock.t1)
    }

    @Test func aNewerLocalPreparedDatePiggybacksOneUpload() async throws {
        let library = try makeSyncTestLibrary()
        let made = clock.t0
        try seedRecipe(
            Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t1, lastPrepared: made, lastModifiedPreparedDate: clock.t2),
            agreed: true, in: library
        )
        Stub.reset(routes: try routes(manifest: [
            manifestEntry("r1", modified: clock.t1, lastPrepared: nil, preparedStamp: clock.t0),
        ]))

        let engine = makeSyncEngine(database: library)
        try await engine.sync()

        let puts = Stub.requests("PUT", "/api/recipes/r1")
        #expect(puts.count == 1)
        let sent = try wireDecode(ServerRecipe.self, from: try #require(puts.first).body)
        #expect(sent.lastPrepared == made)
        #expect(sent.lastModifiedPreparedDate == clock.t2)
        #expect(sent.lastModifiedDate == clock.t1, "the body stamp is re-sent unchanged")
        // (`itemsUploaded` also counts the migrator's default courses and categories going up on a
        // fresh library, so the recipe traffic is judged by the requests above.)
        let progress = await engine.progress
        #expect(progress.uploadedRecipeIds.isEmpty, "not a body upload")
    }

    @Test func aNewerServerPreparedDateIsWrittenWithoutTouchingLastModified() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t1), agreed: true, in: library)
        let before: String = try #require(try recipeRow("r1", in: library))["lastModifiedDate"]
        let made = clock.t3
        Stub.reset(routes: try routes(manifest: [
            manifestEntry("r1", modified: clock.t1, lastPrepared: made, preparedStamp: clock.t2),
        ]))

        let engine = makeSyncEngine(database: library)
        try await engine.sync()

        let row = try #require(try recipeRow("r1", in: library))
        #expect(row["lastPrepared"] == made)
        #expect(row["lastModifiedPreparedDate"] == clock.t2)
        let after: String = row["lastModifiedDate"]
        #expect(after == before, "the targeted write leaves the body stamp byte-identical")
        #expect(Stub.requests("PUT", "/api/recipes/r1").isEmpty)
        let progress = await engine.progress
        #expect(progress.itemsDownloaded == 1)
        #expect(progress.downloadedRecipeIds.isEmpty)
    }

    @Test func aNilStampNeverWins() async throws {
        let library = try makeSyncTestLibrary()
        // A date set by a client that predates the stamp: no stamp, so it never pushes.
        try seedRecipe(
            Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t1, lastPrepared: clock.t0, lastModifiedPreparedDate: nil),
            agreed: true, in: library
        )
        Stub.reset(routes: try routes(manifest: [manifestEntry("r1", modified: clock.t1)]))

        let engine = makeSyncEngine(database: library)
        try await engine.sync()

        #expect(Stub.requests("PUT", "/api/recipes/r1").isEmpty)
        #expect(Stub.requests("POST", "/api/recipes").isEmpty)
        let row = try #require(try recipeRow("r1", in: library))
        #expect(row["lastPrepared"] == clock.t0)
        #expect(row["lastModifiedPreparedDate"] == nil as Date?)
        let progress = await engine.progress
        #expect(progress.itemsDownloaded == 0)
    }
}
