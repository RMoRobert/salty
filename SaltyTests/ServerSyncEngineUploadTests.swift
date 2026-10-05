//
//  ServerSyncEngineUploadTests.swift
//  SaltyTests
//
//  The recipe body's upload direction and the delta download, driven through a full `sync()`
//  against the stub server: a newer local body goes up exactly once (PUT when the server has the
//  recipe, POST when it doesn't) without the force marker, equal stamps move nothing but still get
//  recorded as agreement, and the paged delta is consumed across pages and refused when short.
//

import Testing
import Foundation
import GRDB
@testable import Salty
import SaltyCore

@Suite(.serialized)
struct ServerSyncEngineUploadTests {
    private typealias Stub = SyncEngineStubURLProtocol
    private let clock = SyncTestClock.self

    private func routes(manifest: [ManifestEntry], delta: [ServerRecipe] = [],
                        lastSync: Date? = SyncTestClock.t1, extra: [Stub.Route] = []) throws -> [Stub.Route] {
        extra + [
            .init("GET", "/api/recipes/sync/manifest", body: try wireJSON(manifest)),
            .init("GET", "/api/recipes", body: try wireJSON(delta)),
        ] + syncBaseRoutes(lastSync: lastSync)
    }

    @Test func aNewerLocalBodyIsPutOnceWithoutTheForceMarker() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t2), in: library)
        // The server has an older copy: it answers HEAD, so the upload is a PUT.
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1)],
            extra: [.init("HEAD", "/api/recipes/r1", body: "")]
        ))

        let engine = makeSyncEngine(database: library)
        try await engine.sync()

        let puts = Stub.requests("PUT", "/api/recipes/r1")
        #expect(puts.count == 1)
        #expect(Stub.requests("POST", "/api/recipes").isEmpty)
        let put = try #require(puts.first)
        #expect(put.headers[ServerSyncEngine.forceWriteHeader] == nil)
        let sent = try wireDecode(ServerRecipe.self, from: put.body)
        #expect(sent.name == "Loaf")
        #expect(sent.lastModifiedDate == clock.t2)

        let progress = await engine.progress
        #expect(progress.uploadedRecipeIds == ["r1"])
        #expect(progress.downloadedRecipeIds.isEmpty)
        let agreed: Date? = try #require(try recipeRow("r1", in: library))["syncedModifiedDate"]
        #expect(agreed == clock.t2, "the upload is recorded as agreement at the uploaded stamp")
        #expect(syncWasCompleted())
    }

    @Test func aRecipeTheServerLacksIsPosted() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t2), in: library)
        Stub.reset(routes: try routes(
            manifest: [],
            extra: [.init("HEAD", "/api/recipes/r1", body: "", status: 404)]
        ))

        try await makeSyncEngine(database: library).sync()

        #expect(Stub.requests("POST", "/api/recipes").count == 1)
        #expect(Stub.requests("PUT", "/api/recipes/r1").isEmpty)
        let posted = try wireDecode(ServerRecipe.self, from: try #require(Stub.requests("POST", "/api/recipes").first).body)
        #expect(posted.id == "r1")
    }

    @Test func equalStampsMoveNothingAndAreRecordedAsAgreement() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t1), in: library)
        Stub.reset(routes: try routes(manifest: [manifestEntry("r1", modified: clock.t1)]))

        let engine = makeSyncEngine(database: library)
        try await engine.sync()

        let recipeRequests = Stub.recorded.filter { $0.path.hasPrefix("/api/recipes/r1") || ($0.path == "/api/recipes" && $0.method != "GET") }
        #expect(recipeRequests.isEmpty, "no HEAD, PUT or POST for a recipe both sides hold at the same stamp")
        let progress = await engine.progress
        #expect(progress.uploadedRecipeIds.isEmpty)
        #expect(progress.downloadedRecipeIds.isEmpty)
        let agreed: Date? = try #require(try recipeRow("r1", in: library))["syncedModifiedDate"]
        #expect(agreed == clock.t1, "already identical on both sides counts as agreed")
    }

    @Test func theDeltaIsConsumedAcrossPages() async throws {
        let library = try makeSyncTestLibrary()
        let ids = (1...101).map { "r\($0)" }
        let manifest = ids.map { manifestEntry($0, modified: clock.t1) }
        let bodies = ids.map { serverRecipe($0, name: "Recipe \($0)", modified: clock.t1) }
        let total = ["X-Total-Count": "101"]
        // A first sync: no watermark, so the whole table is paged through.
        Stub.reset(routes: try routes(
            manifest: manifest, lastSync: nil,
            extra: [
                .init("GET", "/api/recipes", query: "page=0&", body: try wireJSON(Array(bodies[0..<100])), headers: total),
                .init("GET", "/api/recipes", query: "page=1&", body: try wireJSON(Array(bodies[100...])), headers: total),
            ]
        ))

        let engine = makeSyncEngine(database: library)
        try await engine.sync()

        let pages = Stub.requests("GET", "/api/recipes").compactMap(\.query)
        #expect(pages.contains { $0.contains("page=0&") })
        #expect(pages.contains { $0.contains("page=1&") })
        #expect(!pages.contains { $0.contains("page=2&") })
        #expect(try recipeCount(in: library) == 101)
        let progress = await engine.progress
        #expect(progress.downloadedRecipeIds.count == 101)
        #expect(syncWasCompleted())
    }

    @Test func aShortDeltaAbortsBeforeAnythingIsDeletedOrCompleted() async throws {
        let library = try makeSyncTestLibrary()
        let manifest = ["r1", "r2", "r3"].map { manifestEntry($0, modified: clock.t1) }
        let bodies = ["r1", "r2"].map { serverRecipe($0, name: $0, modified: clock.t1) }
        Stub.reset(routes: try routes(
            manifest: manifest, lastSync: nil,
            extra: [.init("GET", "/api/recipes", query: "page=0&", body: try wireJSON(bodies), headers: ["X-Total-Count": "3"])]
        ))

        await #expect(throws: SyncError.self) {
            try await makeSyncEngine(database: library).sync()
        }
        #expect(try recipeCount(in: library) == 0, "nothing from a delta that doesn't add up is written")
        #expect(!syncWasCompleted())
    }
}
