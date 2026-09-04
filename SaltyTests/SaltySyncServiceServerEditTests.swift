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
//  - Classifier deletes carry `If-Match` with the timestamp the delete decision was based on, and
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
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SyncRouteStubURLProtocol.self]
        return SaltySyncService(
            session: URLSession(configuration: config),
            credentials: InMemorySyncCredentialStore(password: "pw", deviceToken: "salty_test")
        )
    }

    /// The always-needed routes: the token check every sync opens with, device registration (a
    /// returning device with a watermark one hour ago), sync completion, and empty recipe
    /// manifest/delta. Entity list routes ride on the unrouted-request default ("[]") unless a test
    /// overrides them.
    private func baseRoutes(lastSync: Date) -> [SyncRouteStubURLProtocol.Route] {
        [
            .init(method: "POST", path: "/api/auth/token/verify", body: #"{"username":"tester"}"#),
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

    // MARK: - Conditional classifier deletes

    @Test func classifierDeleteCarriesIfMatchTimestamp() async throws {
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

    @Test func classifierDeleteConflictDownloadsCurrentRowInstead() async throws {
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

    // MARK: - SYNC-016: neither empty side is a mass deletion

    /// The direction that was missing: an empty library must not be read as "every one of these was
    /// deleted here" and pushed at the server.
    ///
    /// A library is empty for the same kinds of reason a server list is — restored from a backup that
    /// predates the recipes, recreated at the old path after being moved, or opened before iCloud
    /// finished bringing it down. This direction loses the shared copy rather than one device's, and
    /// the workflow that reaches it most directly is replacing a device by deleting the local library
    /// and pulling the server's copy back with an ordinary sync.
    ///
    /// SYNC-021 now makes the recipe half of this unconditional — no library, empty or not, deletes a
    /// recipe on the server — so what this pins for recipes is the outcome rather than the guard. The
    /// SYNC-016 guard itself is still live and still needed for courses, categories and tags, which
    /// have no tombstones and so keep the inference SYNC-021 removed from recipes.
    @Test func anEmptyLibraryDoesNotAskTheServerToDeleteEveryRecipe() async throws {
        let database = try makeTestDatabase() // seeds classifiers; no recipes
        let staleWire = SyncWireDate.string(from: Date().addingTimeInterval(-7200))

        // Routed BEFORE baseRoutes, which stubs the manifest as empty: the matcher takes the first hit.
        // The row is fetched now rather than deleted (SYNC-021), so it needs a body to fetch.
        var routes: [SyncRouteStubURLProtocol.Route] = [
            .init(method: "GET", path: "/api/recipes/sync/manifest",
                  body: #"[{"id": "r-only-on-server", "lastModifiedDate": "\#(staleWire)"}]"#),
            .init(method: "GET", path: "/api/recipes/r-only-on-server",
                  body: #"{"id": "r-only-on-server", "name": "Kept", "lastModifiedDate": "\#(staleWire)"}"#),
        ]
        routes.append(contentsOf: baseRoutes(lastSync: Date().addingTimeInterval(-3600)))
        SyncRouteStubURLProtocol.reset(routes: routes)

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let service = makeService()
            try await service.syncNow(force: true)
        }

        let deletes = SyncRouteStubURLProtocol.recorded.filter { $0.path == "/api/recipes/sync/delete" }
        #expect(deletes.isEmpty, "an empty library cannot vouch for a mass deletion on the server")
    }

    // MARK: - A server-only recipe is taken, not deleted

    /// A recipe the server has and this library does not, stamped BEFORE this device's last sync, is
    /// DOWNLOADED — never deleted from the server.
    ///
    /// The plan reads "older than my watermark" as "I had it and deleted it", which is a guess. A
    /// deliberate deletion never reaches that branch: it travels as a tombstone and is filtered out of
    /// the manifest. What does reach it is a library that lost its memory — pointed at a different
    /// bundle, or restored from a copy older than the watermark the device id carries — and there the
    /// guess destroys recipes nobody deleted. Unlike the case above, the library here is NOT empty, so
    /// the SYNC-016 guard has nothing to object to; this is the gap that guard never covered.
    ///
    /// Mirrors SaltyKMP's `aServerRecipeOlderThanTheWatermarkIsTakenNotDeleted`.
    @Test func aServerRecipeOlderThanTheWatermarkIsTakenNotDeleted() async throws {
        let database = try makeTestDatabase()
        let staleWire = SyncWireDate.string(from: Date().addingTimeInterval(-7200))

        // A local recipe, so "everything is missing" is not what saves the server's copy.
        //
        // Every column the Swift model treats as non-optional is given a value — the same set
        // `coalesceNullRecipeColumns` repairs, and for the same reason: the sync reads every row back
        // as a `Recipe` while reconciling prepared dates, and a NULL in one of these fails that decode.
        // `createdDate` is the easy one to miss. The genuinely-optional columns (nutrition, lastPrepared,
        // image*, servings, courseId) are left NULL, which is what a real library holds.
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO "recipe"
                    ("id", "name", "createdDate", "lastModifiedDate", "source", "sourceDetails",
                     "introduction", "difficulty", "rating", "isFavorite", "wantToMake", "yield",
                     "directions", "ingredients", "notes", "variations", "preparationTimes")
                    VALUES (?, ?, ?, ?, '', '', '', 0, 0, 0, 0, '', '[]', '[]', '[]', '[]', '[]')
                    """,
                arguments: ["mine", "Mine", Date().addingTimeInterval(-120), Date().addingTimeInterval(-60)]
            )
        }

        var routes: [SyncRouteStubURLProtocol.Route] = [
            .init(method: "GET", path: "/api/recipes/sync/manifest",
                  body: #"[{"id": "theirs", "lastModifiedDate": "\#(staleWire)"}]"#),
            .init(method: "GET", path: "/api/recipes/theirs",
                  body: #"{"id": "theirs", "name": "From the other library", "lastModifiedDate": "\#(staleWire)"}"#),
        ]
        routes.append(contentsOf: baseRoutes(lastSync: Date().addingTimeInterval(-3600)))
        SyncRouteStubURLProtocol.reset(routes: routes)

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let service = makeService()
            try await service.syncNow(force: true)
        }

        let deletes = SyncRouteStubURLProtocol.recorded.filter { $0.path == "/api/recipes/sync/delete" }
        #expect(deletes.isEmpty, "a recipe this library cannot prove it deleted stays on the server")

        // Read the column, not the struct: `Recipe` decoding is beside the point here, and a downloaded
        // row leaves the genuinely-optional `nutrition` NULL, which this suite has been seen to trip over
        // when it runs alongside others.
        let landedName = try await database.read { db in
            try String.fetchOne(db, sql: #"SELECT "name" FROM "recipe" WHERE "id" = ?"#, arguments: ["theirs"])
        }
        #expect(landedName == "From the other library", "and is taken, so the next sync sees an ordinary row")
    }

    // MARK: - Force re-sync marks its overwrites

    @Test func forceResyncToServerMarksEveryClassifierWriteForced() async throws {
        let database = try makeTestDatabase() // migration seeds give it local courses + categories
        SyncRouteStubURLProtocol.reset(routes: baseRoutes(lastSync: Date().addingTimeInterval(-3600)))

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let service = makeService()
            try await service.forceFullResyncToServer()
        }

        let classifierWrites = SyncRouteStubURLProtocol.recorded.filter { req in
            (req.method == "POST" || req.method == "PUT") &&
            (req.path.hasPrefix("/api/courses") || req.path.hasPrefix("/api/categories") || req.path.hasPrefix("/api/tags"))
        }
        // The migration seeds guarantee there was something to push.
        #expect(!classifierWrites.isEmpty)
        #expect(classifierWrites.allSatisfy { $0.headers[SaltySyncService.forceWriteHeader] == "1" })
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

    /// A save announces itself so the *other* windows editing that list reload — the editor that made
    /// it must be able to tell its own announcement apart, or it would reload mid-keystroke.
    @Test func editorChangeIsOwnedOnlyByTheEditorThatMadeIt() {
        let notifier = ShoppingListChangeNotifier.shared
        let list = "notifier-owner-\(UUID().uuidString)"
        let mine = UUID()
        let theirs = UUID()

        notifier.noteEditorChange(listId: list, source: mine)

        #expect(notifier.changeCount(for: list) == 1)
        #expect(notifier.isOwnChange(listId: list, source: mine))
        #expect(!notifier.isOwnChange(listId: list, source: theirs))
    }

    /// Two windows on one list: whoever wrote last owns the change, and everyone else reloads.
    @Test func latestEditorChangeTakesOverOwnership() {
        let notifier = ShoppingListChangeNotifier.shared
        let list = "notifier-handover-\(UUID().uuidString)"
        let first = UUID()
        let second = UUID()

        notifier.noteEditorChange(listId: list, source: first)
        notifier.noteEditorChange(listId: list, source: second)

        #expect(notifier.changeCount(for: list) == 2)
        #expect(notifier.isOwnChange(listId: list, source: second))
        #expect(!notifier.isOwnChange(listId: list, source: first))
    }

    /// Sync and the "Add to Shopping List" sheet belong to no editor, so every open editor reloads —
    /// including one that happened to write the list a moment earlier.
    @Test func externalChangeBelongsToNoEditor() {
        let notifier = ShoppingListChangeNotifier.shared
        let list = "notifier-external-\(UUID().uuidString)"
        let editor = UUID()

        notifier.noteEditorChange(listId: list, source: editor)
        notifier.noteExternalChange(listId: list)

        #expect(notifier.changeCount(for: list) == 2)
        #expect(!notifier.isOwnChange(listId: list, source: editor))
    }

    /// Ownership is per list for the same reason the counters are: one editor's save must not make
    /// another list's pending change look like it was already handled.
    @Test func ownershipIsPerList() {
        let notifier = ShoppingListChangeNotifier.shared
        let a = "notifier-own-a-\(UUID().uuidString)"
        let b = "notifier-own-b-\(UUID().uuidString)"
        let editor = UUID()

        notifier.noteEditorChange(listId: a, source: editor)
        notifier.noteExternalChange(listId: b)

        #expect(notifier.isOwnChange(listId: a, source: editor))
        #expect(!notifier.isOwnChange(listId: b, source: editor))
    }
}
