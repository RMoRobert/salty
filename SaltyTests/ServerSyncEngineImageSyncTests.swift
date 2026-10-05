//
//  ServerSyncEngineImageSyncTests.swift
//  SaltyTests
//
//  Every branch of the image pass, which is keyed on `lastModifiedImageDate` independently of the
//  body: with equal stamps an image is still propagated to the side that never got it and a lost
//  local file is recovered; the newer side otherwise wins, pushing bytes, pulling bytes, or
//  carrying a removal; nothing moves for an unchanged image; and failures are tallied, failing the
//  sync only when no image moved at all.
//
//  Bodies are held at equal, agreed stamps throughout so the body pass stays quiet.
//

import Testing
import Foundation
import GRDB
@testable import Salty
import SaltyCore

@Suite(.serialized)
struct ServerSyncEngineImageSyncTests {
    private typealias Stub = SyncEngineStubURLProtocol
    private let clock = SyncTestClock.self
    private let bytes = "photo-bytes"

    private func routes(manifest: [ManifestEntry], extra: [Stub.Route] = []) throws -> [Stub.Route] {
        extra + [.init("GET", "/api/recipes/sync/manifest", body: try wireJSON(manifest))]
            + syncBaseRoutes(lastSync: SyncTestClock.t1)
    }

    private func localRecipe(filename: String? = nil, imageDate: Date? = nil) -> Recipe {
        Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t1,
               imageFilename: filename, lastModifiedImageDate: imageDate)
    }

    private var imageGETs: [Stub.Recorded] {
        Stub.recorded.filter { $0.method == "GET" && $0.path.hasPrefix("/api/recipes/images/") }
    }

    @Test func equalStampsWithOnlyAServerFileDownloadOnce() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(localRecipe(), agreed: true, in: library)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1, imageFilename: "r1.jpg", imageDate: nil)],
            extra: [.init("GET", "/api/recipes/images/r1.jpg", body: bytes)]
        ))
        let images = InMemorySyncImageStore()

        let engine = makeSyncEngine(database: library, images: images)
        try await engine.sync()

        #expect(imageGETs.count == 1)
        #expect(images.files["r1.jpg"] == Data(bytes.utf8))
        let row = try #require(try recipeRow("r1", in: library))
        #expect(row["imageFilename"] == "r1.jpg")
        #expect(row["imageThumbnailData"] == InMemorySyncImageStore.thumbnail)
        let progress = await engine.progress
        #expect(progress.imagesDownloaded == 1)
        #expect(progress.imagesUploaded == 0)
    }

    @Test func aLocalFilenameWhoseFileIsMissingIsRedownloaded() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(localRecipe(filename: "r1.jpg", imageDate: clock.t1), agreed: true, in: library)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1, imageFilename: "r1.jpg", imageDate: clock.t1)],
            extra: [.init("GET", "/api/recipes/images/r1.jpg", body: bytes)]
        ))
        let images = InMemorySyncImageStore()   // the row names a file the store doesn't have

        try await makeSyncEngine(database: library, images: images).sync()

        #expect(imageGETs.count == 1)
        #expect(images.files["r1.jpg"] == Data(bytes.utf8))
    }

    @Test func aNewerLocalRemovalIsDeletedOnTheServer() async throws {
        let library = try makeSyncTestLibrary()
        // Local is newer but has no bytes to send: that is a removal, carried to the server.
        try seedRecipe(localRecipe(filename: "r1.jpg", imageDate: clock.t2), agreed: true, in: library)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1, imageFilename: "r1.jpg", imageDate: clock.t1)],
            extra: [.init("DELETE", "/api/recipes/r1/image", body: "{}")]
        ))

        let engine = makeSyncEngine(database: library, images: InMemorySyncImageStore())
        try await engine.sync()

        let deletes = Stub.requests("DELETE", "/api/recipes/r1/image")
        #expect(deletes.count == 1)
        #expect(deletes.first?.query?.removingPercentEncoding == "lastModifiedImageDate=\(SyncWireDate.string(from: clock.t2))")
        #expect(imageGETs.isEmpty)
        let progress = await engine.progress
        #expect(progress.imagesUploaded == 1)
    }

    @Test func aNewerLocalImageIsUploadedWithItsStamp() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(localRecipe(filename: "r1.jpg", imageDate: clock.t2), agreed: true, in: library)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1, imageFilename: "r1.jpg", imageDate: clock.t1)],
            extra: [.init("POST", "/api/recipes/r1/image", body: "{}")]
        ))
        let images = InMemorySyncImageStore(files: ["r1.jpg": Data(bytes.utf8)])

        let engine = makeSyncEngine(database: library, images: images)
        try await engine.sync()

        let uploads = Stub.requests("POST", "/api/recipes/r1/image")
        #expect(uploads.count == 1)
        let body = String(decoding: try #require(uploads.first).body, as: UTF8.self)
        #expect(body.contains(bytes))
        #expect(body.contains("name=\"lastModifiedImageDate\""))
        #expect(body.contains(SyncWireDate.string(from: clock.t2)))
        let progress = await engine.progress
        #expect(progress.imagesUploaded == 1)
        #expect(progress.imagesDownloaded == 0)
    }

    @Test func aNewerServerRemovalClearsTheLocalImage() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(localRecipe(filename: "r1.jpg", imageDate: clock.t1), agreed: true, in: library)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1, imageFilename: nil, imageDate: clock.t2)]
        ))
        let images = InMemorySyncImageStore(files: ["r1.jpg": Data(bytes.utf8)])

        try await makeSyncEngine(database: library, images: images).sync()

        let row = try #require(try recipeRow("r1", in: library))
        #expect(row["imageFilename"] == nil as String?)
        #expect(row["lastModifiedImageDate"] == clock.t2)
        #expect(images.deleted == ["r1.jpg"])
    }

    @Test func anUnchangedImageMovesNoBytes() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(localRecipe(filename: "r1.jpg", imageDate: clock.t1), agreed: true, in: library)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1, imageFilename: "r1.jpg", imageDate: clock.t1)]
        ))
        let images = InMemorySyncImageStore(files: ["r1.jpg": Data(bytes.utf8)])

        try await makeSyncEngine(database: library, images: images).sync()

        #expect(Stub.recorded.filter { $0.path.contains("image") }.isEmpty)
    }

    @Test func aFailureWithNothingMovedFailsTheSync() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(localRecipe(), agreed: true, in: library)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1, imageFilename: "r1.jpg", imageDate: nil)],
            extra: [.init("GET", "/api/recipes/images/r1.jpg", body: "", status: 500)]
        ))

        let engine = makeSyncEngine(database: library, images: InMemorySyncImageStore())
        await #expect(throws: SyncError.self) {
            try await engine.sync()
        }
        let progress = await engine.progress
        #expect(progress.imagesFailed == 1)
        #expect(!syncWasCompleted())
    }

    @Test func aFailureBesideASuccessIsTalliedAndTheSyncCompletes() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(localRecipe(), agreed: true, in: library)
        try seedRecipe(Recipe(id: "r2", name: "Rolls", lastModifiedDate: clock.t1), agreed: true, in: library)
        Stub.reset(routes: try routes(
            manifest: [
                manifestEntry("r1", modified: clock.t1, imageFilename: "r1.jpg", imageDate: nil),
                manifestEntry("r2", modified: clock.t1, imageFilename: "r2.jpg", imageDate: nil),
            ],
            extra: [
                .init("GET", "/api/recipes/images/r1.jpg", body: "", status: 500),
                .init("GET", "/api/recipes/images/r2.jpg", body: bytes),
            ]
        ))

        let engine = makeSyncEngine(database: library, images: InMemorySyncImageStore())
        try await engine.sync()

        let progress = await engine.progress
        #expect(progress.imagesFailed == 1)
        #expect(progress.imagesDownloaded == 1)
        #expect(syncWasCompleted())
    }
}
