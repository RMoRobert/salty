//
//  ServerSyncEngineBodyDownloadTests.swift
//  SaltyTests
//
//  What `writeDownloadedRecipe` keeps and drops when a newer server body lands on an existing row:
//  the image columns (owned by the image pass), a newer local "last made" pair, a course the
//  library doesn't have (nulled rather than failing the foreign key), and the category and tag
//  links, which follow the body but only to classifiers that exist here.
//

import Testing
import Foundation
import GRDB
@testable import Salty
import SaltyCore

@Suite(.serialized)
struct ServerSyncEngineBodyDownloadTests {
    private typealias Stub = SyncEngineStubURLProtocol
    private let clock = SyncTestClock.self

    private func routes(manifest: [ManifestEntry], delta: [ServerRecipe]) throws -> [Stub.Route] {
        [
            .init("GET", "/api/recipes/sync/manifest", body: try wireJSON(manifest)),
            .init("GET", "/api/recipes", body: try wireJSON(delta)),
        ] + syncBaseRoutes(lastSync: SyncTestClock.t1)
    }

    @Test func aNewerServerBodyLeavesTheImageAndANewerPreparedPairAlone() async throws {
        let library = try makeSyncTestLibrary()
        let images = InMemorySyncImageStore(files: ["r1.jpg": Data("photo".utf8)])
        let thumbnail = Data("local thumb".utf8)
        let made = clock.t0
        try seedRecipe(
            Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t1,
                   lastPrepared: made, lastModifiedPreparedDate: clock.t2,
                   imageFilename: "r1.jpg", imageThumbnailData: thumbnail, lastModifiedImageDate: clock.t1),
            agreed: true, in: library
        )
        // The server's body is newer, carries no image and an older prepared pair.
        let serverBody = serverRecipe("r1", name: "Server Loaf", modified: clock.t2, lastPrepared: nil, preparedStamp: clock.t0)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t2, imageFilename: "r1.jpg", imageDate: clock.t1,
                                     lastPrepared: nil, preparedStamp: clock.t0)],
            delta: [serverBody]
        ))

        let engine = makeSyncEngine(database: library, images: images)
        try await engine.sync()

        let row = try #require(try recipeRow("r1", in: library))
        #expect(row["name"] == "Server Loaf")
        #expect(row["imageFilename"] == "r1.jpg")
        #expect(row["imageThumbnailData"] == thumbnail)
        #expect(row["lastModifiedImageDate"] == clock.t1)
        #expect(row["lastPrepared"] == made, "the newer local prepared pair survives the body download")
        #expect(row["lastModifiedPreparedDate"] == clock.t2)
        #expect(Stub.recorded.filter { $0.path.hasPrefix("/api/recipes/images/") }.isEmpty, "no image bytes moved for a text-only edit")
        let progress = await engine.progress
        #expect(progress.downloadedRecipeIds == ["r1"])
    }

    @Test func aCourseTheLibraryLacksIsNulledAndAKnownOneIsKept() async throws {
        let library = try makeSyncTestLibrary()
        try seedClassifier("course", id: "course-1", name: "Dinner", modified: clock.t1, in: library)
        let bodies = [
            serverRecipe("r1", name: "Orphan", modified: clock.t2, courseId: "course-gone"),
            serverRecipe("r2", name: "Filed", modified: clock.t2, courseId: "course-1"),
        ]
        Stub.reset(routes: try routes(
            manifest: bodies.map { manifestEntry($0.id, modified: clock.t2) },
            delta: bodies
        ))

        try await makeSyncEngine(database: library).sync()

        let orphan = try #require(try recipeRow("r1", in: library))
        let filed = try #require(try recipeRow("r2", in: library))
        #expect(orphan["courseId"] == nil as String?)
        #expect(filed["courseId"] == "course-1")
    }

    @Test func categoryAndTagLinksFollowTheBodyOnlyToKnownClassifiers() async throws {
        let library = try makeSyncTestLibrary()
        try seedClassifier("category", id: "cat-1", name: "Bread", modified: clock.t1, in: library)
        try seedClassifier("tag", id: "tag-1", name: "weeknight", modified: clock.t1, in: library)
        var body = serverRecipe("r1", name: "Loaf", modified: clock.t2)
        body.categoryIds = ["cat-1", "cat-ghost"]
        body.tagIds = ["tag-ghost", "tag-1"]
        Stub.reset(routes: try routes(manifest: [manifestEntry("r1", modified: clock.t2)], delta: [body]))

        try await makeSyncEngine(database: library).sync()

        let (categories, tags) = try await library.read { db in
            (try String.fetchAll(db, sql: #"SELECT "categoryId" FROM "recipeCategory" WHERE "recipeId" = 'r1'"#),
             try String.fetchAll(db, sql: #"SELECT "tagId" FROM "recipeTag" WHERE "recipeId" = 'r1'"#))
        }
        #expect(categories == ["cat-1"])
        #expect(tags == ["tag-1"])
    }
}
