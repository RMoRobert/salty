//
//  SaltySyncServiceErrorPathTests.swift
//  SaltyTests
//
//  Verifies the sync error-handling pass: server calls that previously logged a warning and returned
//  (silently "succeeding", letting syncNow advance lastSyncDate) now THROW on a non-2xx response. Driven
//  through an injected URLProtocol-stubbed URLSession so no live server is needed. Serialized because the
//  stub's response is shared global state and the service reads serverUrl from UserDefaults.standard.
//

import Testing
import Foundation
@testable import Salty

/// A URLProtocol that answers every request with a canned status code and body.
final class StubURLProtocol: URLProtocol {
    struct Stub { var status: Int; var body: Data }
    nonisolated(unsafe) static var stub = Stub(status: 200, body: Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let stub = Self.stub
        let url = request.url ?? URL(string: "https://stub.local")!
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
@Suite(.serialized)
struct SaltySyncServiceErrorPathTests {

    /// A service whose every request resolves to `status` via the stub protocol.
    private func makeService(status: Int, body: Data = Data()) -> SaltySyncService {
        UserDefaults.standard.set("https://stub.local", forKey: "serverUrl")
        StubURLProtocol.stub = .init(status: status, body: body)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return SaltySyncService(session: URLSession(configuration: config))
    }

    // MARK: - completeSyncOnServer

    @Test func completeSyncThrowsOnServerError() async {
        let service = makeService(status: 500)
        await #expect(throws: SyncError.self) {
            try await service.completeSyncOnServer()
        }
    }

    /// The stub works both ways: a 2xx must NOT throw (so a real completion still advances lastSyncDate).
    @Test func completeSyncSucceedsOnOK() async throws {
        let service = makeService(status: 200)
        try await service.completeSyncOnServer()
    }

    // MARK: - deleteRecipesOnServer

    @Test func deleteRecipesThrowsOnServerError() async {
        let service = makeService(status: 503)
        await #expect(throws: SyncError.self) {
            try await service.deleteRecipesOnServer(recipeIds: ["r1", "r2"])
        }
    }

    @Test func deleteRecipesSucceedsOnOK() async throws {
        let service = makeService(status: 200, body: Data(#"{"deleted":2}"#.utf8))
        try await service.deleteRecipesOnServer(recipeIds: ["r1", "r2"])
    }

    // MARK: - downloadImage

    /// A 404 (or any non-200) must throw rather than return — otherwise the caller counts a failed
    /// download as a synced image. The throw happens before any database access.
    @Test func downloadImageThrowsOnNotFound() async {
        let service = makeService(status: 404)
        await #expect(throws: SyncError.self) {
            try await service.downloadImage(filename: "missing.jpg", for: "r1", imageDate: nil)
        }
    }

    /// A body over the size cap must throw (before any disk/database write), so a hostile or corrupt
    /// server response can't balloon local storage. The cap is injected small so the test doesn't need
    /// a multi-hundred-MB fixture.
    @Test func downloadImageThrowsWhenBodyExceedsSizeCap() async {
        let service = makeService(status: 200, body: Data(count: 64))
        await #expect(throws: SyncError.self) {
            try await service.downloadImage(filename: "big.jpg", for: "r1", imageDate: nil, maxBytes: 32)
        }
    }
}

/// The image filename in a download URL is server-controlled. It must be encoded as a SINGLE path
/// component — in particular "/" must be percent-encoded — so a hostile value can't traverse out of
/// `/api/recipes/images/` and point the authenticated request at another endpoint.
struct SyncImageFilenameEncodingTests {

    @Test func leavesNormalFilenamesUntouched() {
        let filename = "0198B5C6-1234-7ABC-8DEF-0123456789AB.jpg"
        #expect(SaltySyncService.encodedImagePathComponent(filename) == filename)
    }

    @Test func encodesSlashesSoTraversalStaysInsideTheImagesPath() {
        #expect(SaltySyncService.encodedImagePathComponent("../../api/auth/login")
                == "..%2F..%2Fapi%2Fauth%2Flogin")
    }

    @Test func encodesQueryAndFragmentDelimiters() {
        let encoded = SaltySyncService.encodedImagePathComponent("x.jpg?admin=1#frag")
        #expect(encoded == "x.jpg%3Fadmin=1%23frag")
    }
}
