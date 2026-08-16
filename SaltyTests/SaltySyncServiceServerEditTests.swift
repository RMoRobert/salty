//
//  SaltySyncServiceServerEditTests.swift
//  SaltyTests
//
//  Covers the client behaviors that make server-originated edits (another device, or the server's
//  web UI) safe:
//
//  - Sync fires `ShoppingListChangeNotifier` for every list it writes or deletes locally, so an
//    open checklist/freeform editor reloads instead of saving its stale in-memory copy back over
//    the downloaded change.
//  - Vocabulary deletes carry `If-Match` with the timestamp the delete decision was based on, and
//    a 409 (future server: "the row changed after your fetch") downloads the current row instead
//    of deleting. Today's server ignores the header, so behavior is unchanged until it doesn't.
//  - The force re-sync-to-server paths mark every overwrite with `X-Salty-Force`, so a future
//    server-side stale-write guard can distinguish a deliberate mirror push; regular sync must
//    never send it.
//
//  Driven through a full `syncNow()` against a URL-routed stub session and a real migrated
//  temporary database — the same seams the error-path tests use, extended with per-path routing.
//  Serialized: the stub's routes/recordings are shared global state, the service reads its
//  configuration from UserDefaults.standard, and swift-dependencies resolution must not race
//  across suites.
//

import Testing
import Foundation
import GRDB
import SQLiteData
@testable import Salty
import SaltyCore

/// A URLProtocol that answers requests by first-match routing on method + path, and records every
/// request (method, path, headers) so tests can assert on what the sync sent.
final class SyncRouteStubURLProtocol: URLProtocol {
    struct Route {
        let method: String
        /// Exact path unless `isPrefix`, in which case any path with this prefix matches.
        let path: String
        var isPrefix = false
        var status = 200
        var body = "[]"
    }
    struct Recorded {
        let method: String
        let path: String
        let headers: [String: String]
    }

    nonisolated(unsafe) static var routes: [Route] = []
    nonisolated(unsafe) static var recorded: [Recorded] = []

    static func reset(routes: [Route]) {
        self.routes = routes
        recorded = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        Self.recorded.append(Recorded(method: method, path: path, headers: request.allHTTPHeaderFields ?? [:]))

        let route = Self.routes.first {
            $0.method == method && ($0.isPrefix ? path.hasPrefix($0.path) : path == $0.path)
        }
        // Unrouted requests answer 200 "[]" — harmless for list GETs and ignored-body writes, and
        // an object-shaped decode of it fails loudly, which surfaces a missing route in the test.
        let status = route?.status ?? 200
        let body = route?.body ?? "[]"

        let url = request.url ?? URL(fileURLWithPath: "/")
        if let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                          headerFields: ["Content-Type": "application/json"]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
@Suite(.serialized)
struct SaltySyncServiceServerEditTests {

    /// Builds a fresh, migrated, isolated database (same pattern as DatabaseTests: never call
    /// `appDatabase()` inside a `withDependencies` MUTATION closure).
    private func makeTestDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
        } operation: {
            try appDatabase()
        }
    }

    /// A service wired to the routed stub, with in-memory credentials and a still-valid token so no
    /// login round-trip is needed. Constructed INSIDE `withDependencies` by the caller so its
    /// `@Dependency(\.defaultDatabase)` resolves to the test database.
    private func makeService() -> SaltySyncService {
        UserDefaults.standard.set("https://stub.local", forKey: "serverUrl")
        UserDefaults.standard.set(true, forKey: "serverUse")
        UserDefaults.standard.set("tester", forKey: "serverUsername")
        UserDefaults.standard.set(Date().addingTimeInterval(3600), forKey: "serverTokenExpiration")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SyncRouteStubURLProtocol.self]
        return SaltySyncService(
            session: URLSession(configuration: config),
            credentials: InMemorySyncCredentialStore(password: "pw", jwtToken: "test-jwt")
        )
    }

    /// The always-needed routes: device registration (a returning device with a watermark one hour
    /// ago), sync completion, and empty recipe manifest/delta. Entity list routes ride on the
    /// unrouted-request default ("[]") unless a test overrides them.
    private func baseRoutes(lastSync: Date) -> [SyncRouteStubURLProtocol.Route] {
        [
            .init(method: "POST", path: "/api/recipes/sync/device",
                  body: #"{"isFirstSync": false, "lastSyncDate": "\#(SyncWireDate.string(from: lastSync))"}"#),
            .init(method: "POST", path: "/api/recipes/sync/device/", isPrefix: true, body: "{}"),
            .init(method: "GET", path: "/api/recipes/sync/manifest"),
            .init(method: "GET", path: "/api/recipes"),
            .init(method: "POST", path: "/api/courses", isPrefix: true, body: "{}"),
            .init(method: "POST", path: "/api/categories", isPrefix: true, body: "{}"),
            .init(method: "POST", path: "/api/tags", isPrefix: true, body: "{}"),
        ]
    }

    /// Inserts a shopping list row that is fully in agreement with the server at [revision]:
    /// the snapshot's lastModifiedDate matches the row's, so it reads as clean (not dirty).
    private func insertSyncedList(
        _ db: any DatabaseWriter, id: String, name: String, revision: Int64, wireDate: String
    ) async throws {
        // GRDB stores dates as "yyyy-MM-dd HH:mm:ss.SSS" (UTC); the snapshot keeps the wire form.
        let dbDate = wireDate.replacing("T", with: " ").replacing("Z", with: "")
        let snapshot = #"{"id":"\#(id)","lastModifiedDate":"\#(wireDate)","revision":\#(revision)}"#
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO "shoppingList"
                    ("id", "name", "isFreeform", "contentsForFreeform", "contentsForList",
                     "lastModifiedDate", "syncedRevision", "syncedSnapshot")
                    VALUES (?, ?, 0, NULL, '[]', ?, ?, ?)
                    """,
                arguments: [id, name, dbDate, revision, snapshot]
            )
        }
    }

    // MARK: - Sync notifies open shopping-list editors

    @Test func syncNotifiesForDownloadedAndLocallyDeletedListsOnly() async throws {
        let database = try makeTestDatabase()
        let changed = "list-changed-\(UUID().uuidString)"
        let unchanged = "list-unchanged-\(UUID().uuidString)"
        let deleted = "list-deleted-\(UUID().uuidString)"
        let wireDate = "2026-08-16T10:00:00.000Z"

        try await insertSyncedList(database, id: changed, name: "Groceries", revision: 1, wireDate: wireDate)
        try await insertSyncedList(database, id: unchanged, name: "Hardware", revision: 1, wireDate: wireDate)
        try await insertSyncedList(database, id: deleted, name: "Party", revision: 1, wireDate: wireDate)

        // The server: `changed` moved to revision 2 (a web edit), `unchanged` as agreed, `deleted` gone.
        var routes = baseRoutes(lastSync: Date().addingTimeInterval(-3600))
        routes.append(.init(method: "GET", path: "/api/shoppingLists", body: """
            [{"id": "\(changed)", "name": "Groceries (web)", "isFreeform": false, "contentsForList": [],
              "lastModifiedDate": "2026-08-16T11:00:00.000Z", "revision": 2},
             {"id": "\(unchanged)", "name": "Hardware", "isFreeform": false, "contentsForList": [],
              "lastModifiedDate": "\(wireDate)", "revision": 1}]
            """))
        SyncRouteStubURLProtocol.reset(routes: routes)

        let notifier = ShoppingListChangeNotifier.shared
        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let service = makeService()
            try await service.syncNow(force: true)
        }

        // Exactly the lists whose local rows sync rewrote or removed were announced.
        #expect(notifier.changeCount(for: changed) == 1)
        #expect(notifier.changeCount(for: unchanged) == 0)
        #expect(notifier.changeCount(for: deleted) == 1)

        // And the writes themselves happened: the web edit landed, the deleted list is gone.
        let (newName, newRevision, deletedCount) = try await database.read { db in
            (try String.fetchOne(db, sql: #"SELECT "name" FROM "shoppingList" WHERE "id" = ?"#, arguments: [changed]),
             try Int64.fetchOne(db, sql: #"SELECT "syncedRevision" FROM "shoppingList" WHERE "id" = ?"#, arguments: [changed]),
             try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "shoppingList" WHERE "id" = ?"#, arguments: [deleted]) ?? -1)
        }
        #expect(newName == "Groceries (web)")
        #expect(newRevision == 2)
        #expect(deletedCount == 0)

        // Regular sync must never mark its writes as forced overwrites.
        let forced = SyncRouteStubURLProtocol.recorded.filter { $0.headers[SaltySyncService.forceWriteHeader] != nil }
        #expect(forced.isEmpty)
    }

    // MARK: - Conditional vocabulary deletes

    @Test func vocabularyDeleteCarriesIfMatchTimestamp() async throws {
        let database = try makeTestDatabase()
        let staleDate = Date().addingTimeInterval(-7200)
        let staleWire = SyncWireDate.string(from: staleDate)

        // A server-only category older than the watermark: the client decides to delete it there.
        var routes = baseRoutes(lastSync: Date().addingTimeInterval(-3600))
        routes.append(.init(method: "GET", path: "/api/categories",
                            body: #"[{"id": "cat-gone", "name": "Stale", "lastModifiedDate": "\#(staleWire)"}]"#))
        routes.append(.init(method: "DELETE", path: "/api/categories/", isPrefix: true, body: "{}"))
        SyncRouteStubURLProtocol.reset(routes: routes)

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let service = makeService()
            try await service.syncNow(force: true)
        }

        let deletes = SyncRouteStubURLProtocol.recorded.filter { $0.method == "DELETE" && $0.path == "/api/categories/cat-gone" }
        #expect(deletes.count == 1)
        // The If-Match value is the timestamp the delete decision was based on, verbatim.
        #expect(deletes.first?.headers["If-Match"] == staleWire)

        // And it was not resurrected locally.
        let localCount = try await database.read { db in
            try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "category" WHERE "id" = 'cat-gone'"#) ?? -1
        }
        #expect(localCount == 0)
    }

    @Test func vocabularyDeleteConflictDownloadsCurrentRowInstead() async throws {
        let database = try makeTestDatabase()
        let staleWire = SyncWireDate.string(from: Date().addingTimeInterval(-7200))
        let currentWire = SyncWireDate.string(from: Date().addingTimeInterval(-10))

        // Same setup, but the server refuses: the category changed after our fetch (a web rename
        // racing this sync). The 409 body is the current row — download it instead of deleting.
        var routes = baseRoutes(lastSync: Date().addingTimeInterval(-3600))
        routes.append(.init(method: "GET", path: "/api/categories",
                            body: #"[{"id": "cat-kept", "name": "Stale", "lastModifiedDate": "\#(staleWire)"}]"#))
        routes.append(.init(method: "DELETE", path: "/api/categories/", isPrefix: true, status: 409,
                            body: #"{"id": "cat-kept", "name": "Renamed on web", "lastModifiedDate": "\#(currentWire)"}"#))
        SyncRouteStubURLProtocol.reset(routes: routes)

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let service = makeService()
            try await service.syncNow(force: true)
        }

        let localName = try await database.read { db in
            try String.fetchOne(db, sql: #"SELECT "name" FROM "category" WHERE "id" = 'cat-kept'"#)
        }
        #expect(localName == "Renamed on web")
    }

    // MARK: - Force re-sync marks its overwrites

    @Test func forceResyncToServerMarksEveryVocabularyWriteForced() async throws {
        let database = try makeTestDatabase() // migration seeds give it local courses + categories
        SyncRouteStubURLProtocol.reset(routes: baseRoutes(lastSync: Date().addingTimeInterval(-3600)))

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let service = makeService()
            try await service.forceFullResyncToServer()
        }

        let vocabWrites = SyncRouteStubURLProtocol.recorded.filter { req in
            (req.method == "POST" || req.method == "PUT") &&
            (req.path.hasPrefix("/api/courses") || req.path.hasPrefix("/api/categories") || req.path.hasPrefix("/api/tags"))
        }
        // The migration seeds guarantee there was something to push.
        #expect(!vocabWrites.isEmpty)
        #expect(vocabWrites.allSatisfy { $0.headers[SaltySyncService.forceWriteHeader] == "1" })
    }
}

// MARK: - Notifier unit behavior

@MainActor
struct ShoppingListChangeNotifierTests {

    /// Counters are per list: several lists changed in one sync pass must each read their own
    /// change, not just the last one announced (SwiftUI coalesces `onChange` deliveries).
    @Test func countsArePerList() {
        let notifier = ShoppingListChangeNotifier.shared
        let a = "notifier-a-\(UUID().uuidString)"
        let b = "notifier-b-\(UUID().uuidString)"

        notifier.noteExternalChange(listId: a)
        notifier.noteExternalChange(listId: b)
        notifier.noteExternalChange(listId: a)

        #expect(notifier.changeCount(for: a) == 2)
        #expect(notifier.changeCount(for: b) == 1)
    }

    @Test func unknownListReadsZero() {
        #expect(ShoppingListChangeNotifier.shared.changeCount(for: "never-touched-\(UUID().uuidString)") == 0)
    }
}
