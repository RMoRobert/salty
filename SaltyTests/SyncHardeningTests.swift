//
//  SyncHardeningTests.swift
//  SaltyTests
//
//  The resilience changes around a sync: uploads trust the manifest instead of asking with a HEAD, a
//  recipe brought back under a deleted id keeps its tombstone from being pushed, a recipe the server
//  lacks gets no image upload, agreement writes skip rows that already match, server text shown to
//  the user is capped, auto-sync backs off after failures, and thumbnails come from a downsample.
//

import Testing
import Foundation
import GRDB
import ImageIO
@testable import Salty
import SaltyCore

@Suite(.serialized)
struct ServerSyncEngineHardeningTests {
    private typealias Stub = SyncEngineStubURLProtocol
    private let clock = SyncTestClock.self

    private func routes(manifest: [ManifestEntry], extra: [Stub.Route] = []) throws -> [Stub.Route] {
        extra + [
            .init("GET", "/api/recipes/sync/manifest", body: try wireJSON(manifest)),
            .init("GET", "/api/recipes", body: "[]"),
        ] + syncBaseRoutes(lastSync: SyncTestClock.t1)
    }

    @Test func uploadsUseTheManifestInsteadOfAHead() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t2), in: library)
        try seedRecipe(Recipe(id: "r2", name: "Rolls", lastModifiedDate: clock.t2), in: library)
        Stub.reset(routes: try routes(manifest: [manifestEntry("r1", modified: clock.t1)]))

        try await makeSyncEngine(database: library).sync()

        #expect(Stub.recorded.filter { $0.method == "HEAD" }.isEmpty)
        #expect(Stub.requests("PUT", "/api/recipes/r1").count == 1, "in the manifest, so updated")
        let posted = Stub.requests("POST", "/api/recipes").map { try? wireDecode(ServerRecipe.self, from: $0.body).id }
        #expect(posted == ["r2"], "not in the manifest, so created")
    }

    @Test func aPutRefusedForARecipeDeletedSinceTheManifestBecomesAPost() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t2), in: library)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1)],
            extra: [
                .init("PUT", "/api/recipes/r1", body: #"{"error": "Recipe not found"}"#, status: 404),
                .init("HEAD", "/api/recipes/r1", body: "", status: 404),
            ]
        ))

        try await makeSyncEngine(database: library).sync()

        #expect(Stub.requests("PUT", "/api/recipes/r1").count == 1)
        #expect(Stub.requests("HEAD", "/api/recipes/r1").count == 1, "asked only after the PUT failed")
        #expect(Stub.requests("POST", "/api/recipes").count == 1)
        #expect(syncWasCompleted())
    }

    @Test func aPutRefusedForAnotherReasonStillFails() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t2), in: library)
        Stub.reset(routes: try routes(
            manifest: [manifestEntry("r1", modified: clock.t1)],
            extra: [
                .init("PUT", "/api/recipes/r1", body: "", status: 500),
                .init("HEAD", "/api/recipes/r1", body: ""),
            ]
        ))

        await #expect(throws: SyncError.self) {
            try await makeSyncEngine(database: library).sync()
        }
        #expect(Stub.requests("POST", "/api/recipes").isEmpty)
    }

    @Test func aTombstoneForARecipeThatExistsAgainIsDroppedNotPushed() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t1), agreed: true, in: library)
        try await library.write { db in try RecipeTombstoneWriter.recordDeletion("r1", in: db) }
        Stub.reset(routes: try routes(manifest: [manifestEntry("r1", modified: clock.t1)]))

        try await makeSyncEngine(database: library).sync()

        #expect(Stub.requests("POST", "/api/recipes/sync/delete").isEmpty)
        let pending = try await library.read { db in try RecipeTombstoneWriter.pending(in: db) }
        #expect(pending.isEmpty)
        #expect(try recipeCount(in: library) == 1)
        #expect(syncWasCompleted())
    }

    @Test func aRecipeTheServerLacksGetsNoImageUpload() async throws {
        let library = try makeSyncTestLibrary()
        try seedRecipe(Recipe(id: "r1", name: "Loaf", lastModifiedDate: clock.t2,
                              imageFilename: "r1.jpg", lastModifiedImageDate: clock.t2), in: library)
        // The manifest never lists r1, as when its body upload didn't land.
        Stub.reset(routes: try routes(manifest: []))
        let images = InMemorySyncImageStore(files: ["r1.jpg": Data("photo".utf8)])

        let engine = makeSyncEngine(database: library, images: images)
        try await engine.sync()

        #expect(Stub.recorded.filter { $0.path.hasSuffix("/image") }.isEmpty)
        let progress = await engine.progress
        #expect(progress.imagesFailed == 0)
        #expect(syncWasCompleted())
    }
}

struct AgreementNoOpTests {
    @Test func markingAnAgreedRecipeAgainChangesNoRows() throws {
        let queue = try makeSyncTestLibrary()
        try queue.write { db in
            try RecipeWriter.save(Recipe(id: "r1", name: "Loaf", lastModifiedDate: SyncTestClock.t1), in: db, now: SyncTestClock.t1)
            try RecipeAgreementStore.markAgreed(["r1"], in: db)
            #expect(db.changesCount == 1)
            try RecipeAgreementStore.markAgreed(["r1"], in: db)
            #expect(db.changesCount == 0, "already agreed at this stamp, so nothing is written")
            try RecipeAgreementStore.markAllAgreed(in: db)
            #expect(db.changesCount == 0)
        }
    }

    @Test func markingAnAgreedClassifierAgainChangesNoRows() throws {
        let queue = try makeSyncTestLibrary()
        try seedClassifier("category", id: "c1", name: "Bread", modified: SyncTestClock.t1, in: queue)
        try queue.write { db in
            try ClassifierAgreementStore.markAgreed(.category, ["c1"], in: db)
            #expect(db.changesCount == 1)
            try ClassifierAgreementStore.markAgreed(.category, ["c1"], in: db)
            #expect(db.changesCount == 0)
        }
    }
}

struct SyncMessageCapTests {
    @Test func aLongServerMessageIsCutToOneShortLine() throws {
        let long = String(repeating: "stack frame\n", count: 80)
        let body = try JSONSerialization.data(withJSONObject: ["message": long])
        let message = SyncError.httpMessage(status: 500, body: body)
        #expect(message.count <= SyncError.maxServerMessageLength + 1)
        #expect(!message.contains("\n"))
        #expect(message.hasSuffix("…"))
    }

    @Test func aShortServerMessageIsShownAsIs() throws {
        let body = try JSONSerialization.data(withJSONObject: ["error": "Recipe not found"])
        #expect(SyncError.httpMessage(status: 404, body: body) == "Recipe not found")
    }

    @Test func aDatabaseErrorNeverShowsItsSQL() {
        let error = DatabaseError(resultCode: .SQLITE_CONSTRAINT, message: "UNIQUE constraint failed: recipe.id",
                                  sql: "INSERT INTO recipe (id) VALUES (?)")
        let message = friendlySyncMessage(error)
        #expect(!message.contains("INSERT"))
        #expect(!message.contains("recipe.id"))
        #expect(message.contains("database error 19"))
    }

    @Test func anOversizedResponseGetsItsOwnWording() {
        let message = friendlySyncMessage(ResponseTooLargeError(limit: 10, observed: 20))
        #expect(message.contains("more data than a sync accepts"))
    }

    @Test func anUnknownErrorsTextIsCapped() {
        struct Chatty: LocalizedError { var errorDescription: String? { String(repeating: "x", count: 2_000) } }
        #expect(friendlySyncMessage(Chatty()).count <= SyncError.maxServerMessageLength + 1)
    }
}

struct AutoSyncBackoffTests {
    @Test func backoffDoublesFromOneMinuteToHalfAnHour() {
        let minutes = (0...8).map { AutoSyncCoordinator.backoff(afterFailures: $0).components.seconds / 60 }
        #expect(minutes == [0, 1, 2, 4, 8, 16, 30, 30, 30])
    }
}

@MainActor
struct ThumbnailDownsampleTests {
    /// A solid PNG of the given pixel size.
    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func pixelSize(of data: Data) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let type = CGImageSourceGetType(source) as String?
        #expect(type == "public.jpeg")
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test func aWidePhotoBecomesASquareJPEGAtThreeTimesThePointSize() throws {
        let data = try png(width: 3000, height: 1000)
        let thumbnail = try #require(RecipeImageManager.shared.generateThumbnail(from: data, size: CGSize(width: 300, height: 300)))
        let (width, height) = try pixelSize(of: thumbnail)
        #expect(width == 900)
        #expect(height == 900)
    }

    @Test func aSmallImageIsScaledUpToFill() throws {
        let data = try png(width: 120, height: 80)
        let thumbnail = try #require(RecipeImageManager.shared.generateThumbnail(from: data, size: CGSize(width: 300, height: 300)))
        let (width, height) = try pixelSize(of: thumbnail)
        #expect((width, height) == (900, 900))
    }

    @Test func bytesThatArentAnImageGiveNoThumbnail() {
        #expect(RecipeImageManager.shared.generateThumbnail(from: Data("not an image".utf8), size: CGSize(width: 300, height: 300)) == nil)
    }
}

struct LibraryLocationPathTests {
    @Test func theDatabaseFileSitsInsideALibraryBundleInTheChosenFolder() throws {
        let parent = URL.temporaryDirectory.appending(component: "parent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: parent) }

        let file = try FileManager.libraryDatabaseFile(inParent: parent)

        let bundle = FileManager.libraryDirectory(inParent: parent)
        #expect(file.deletingLastPathComponent().standardizedFileURL == bundle.standardizedFileURL)
        #expect(file.lastPathComponent == "\(FileManager.dbFileName).\(FileManager.dbFileExt)")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: bundle.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }
}
