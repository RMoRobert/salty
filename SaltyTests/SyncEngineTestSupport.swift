//
//  SyncEngineTestSupport.swift
//  SaltyTests
//
//  One harness for driving `ServerSyncEngine` directly: an in-memory library, in-memory settings,
//  credentials and image files, and a URL-routed stub session that records every request with its
//  body. The engine's interesting work is private and reached only through `sync()`, so each suite
//  seeds rows, routes the server's answers, runs a sync, and reads the rows and the recordings back.
//
//  Nothing here touches `UserDefaults`, the keychain, or the filesystem: the engine takes all three
//  behind protocols, and the earlier service-level suites' habit of writing `serverUrl` into the
//  standard defaults is what this replaces.
//
//  Rows are read back with raw SQL (GRDB `Row`), never with a StructuredQueries builder: those crash
//  when instantiated from the test bundle. See the note at the top of RecipeWriterTests.
//

import Foundation
import GRDB
import Synchronization
import Testing
@testable import Salty
import SaltyCore

// MARK: - Stub server

/// Answers requests by method + path (+ optional query substring), serving a route's responses in
/// order (the last one repeats), and records everything it was asked, body included. Unrouted
/// requests get 200 `[]`: harmless for list GETs and for writes whose reply is ignored, and an
/// object-shaped decode of it fails loudly, which surfaces a missing route in the test.
final class SyncEngineStubURLProtocol: URLProtocol {
    struct Response: Sendable {
        var status = 200
        var body = "[]"
        var headers: [String: String] = [:]

        init(status: Int = 200, body: String = "[]", headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }
    }

    struct Route: Sendable {
        let method: String
        /// Exact path unless `isPrefix`.
        let path: String
        var isPrefix = false
        /// When set, the request's query string must contain this.
        var query: String?
        var responses: [Response]

        init(_ method: String, _ path: String, isPrefix: Bool = false, query: String? = nil, body: String = "[]",
             status: Int = 200, headers: [String: String] = [:]) {
            self.method = method
            self.path = path
            self.isPrefix = isPrefix
            self.query = query
            self.responses = [Response(status: status, body: body, headers: headers)]
        }

        init(_ method: String, _ path: String, isPrefix: Bool = false, query: String? = nil, responses: [Response]) {
            self.method = method
            self.path = path
            self.isPrefix = isPrefix
            self.query = query
            self.responses = responses
        }
    }

    struct Recorded: Sendable {
        let method: String
        let path: String
        let query: String?
        let headers: [String: String]
        let body: Data
    }

    private struct State {
        var routes: [Route] = []
        var served: [Int: Int] = [:]
        var recorded: [Recorded] = []
    }

    private static let state = Mutex(State())

    static func reset(routes: [Route]) {
        state.withLock { $0 = State(routes: routes) }
    }

    static var recorded: [Recorded] {
        state.withLock { $0.recorded }
    }

    static func requests(_ method: String, _ path: String) -> [Recorded] {
        recorded.filter { $0.method == method && $0.path == path }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let query = request.url?.query
        let body = Self.body(of: request)

        let response = Self.state.withLock { state -> Response in
            state.recorded.append(Recorded(method: method, path: path, query: query,
                                           headers: request.allHTTPHeaderFields ?? [:], body: body))
            guard let index = state.routes.firstIndex(where: { route in
                route.method == method
                    && (route.isPrefix ? path.hasPrefix(route.path) : path == route.path)
                    && (route.query.map { (query ?? "").contains($0) } ?? true)
            }) else { return Response() }
            let served = state.served[index, default: 0]
            state.served[index] = served + 1
            let responses = state.routes[index].responses
            return responses[min(served, responses.count - 1)]
        }

        let url = request.url ?? URL(fileURLWithPath: "/")
        var headers = response.headers
        headers["Content-Type"] = headers["Content-Type"] ?? "application/json"
        if let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: headers) {
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// `URLSession` hands a protocol the body as a stream, not as `httpBody`.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - In-memory stores

final class InMemorySyncSettings: SyncSettingsStore {
    private let state: Mutex<(serverURL: String, username: String)>

    init(serverURL: String = "https://stub.local", username: String = "tester") {
        state = Mutex((serverURL, username))
    }

    func serverURL() -> String { state.withLock { $0.serverURL } }
    func username() -> String { state.withLock { $0.username } }
    func setUsername(_ username: String) { state.withLock { $0.username = username } }
}

/// The library's image files as a dictionary. `saveImage` stores under `<recipeId>.jpg` and hands
/// back a fixed thumbnail, so a test can tell "the row was updated from a download" by its bytes.
final class InMemorySyncImageStore: SyncImageStore {
    static let thumbnail = Data("thumbnail".utf8)

    private let state: Mutex<(files: [String: Data], deleted: [String])>

    init(files: [String: Data] = [:]) {
        state = Mutex((files, []))
    }

    var files: [String: Data] { state.withLock { $0.files } }
    var deleted: [String] { state.withLock { $0.deleted } }

    func loadImage(filename: String) -> Data? {
        state.withLock { $0.files[filename] }
    }

    func saveImage(_ imageData: Data, for recipeId: String) -> (filename: String, thumbnailData: Data)? {
        let filename = "\(recipeId).jpg"
        state.withLock { $0.files[filename] = imageData }
        return (filename, Self.thumbnail)
    }

    func deleteImage(filename: String) {
        state.withLock {
            $0.files.removeValue(forKey: filename)
            $0.deleted.append(filename)
        }
    }

    func deleteImages(for recipeId: String, except keep: String?) {
        state.withLock { state in
            for name in state.files.keys where name.hasPrefix("\(recipeId).") && name != keep {
                state.files.removeValue(forKey: name)
                state.deleted.append(name)
            }
        }
    }
}

// MARK: - Library and engine

/// A fresh in-memory library with the base schema and every shared migration (so the agreement
/// columns exist and sync tracks agreement, as it does on a current device).
func makeSyncTestLibrary() throws -> DatabaseQueue {
    let queue = try DatabaseQueue()
    try saltyMigrator().migrate(queue)
    try runSaltySharedMigrations(queue)
    return queue
}

/// An engine over `database`, talking to the stub through an ephemeral session, enrolled with a
/// device token so no login round-trip is needed.
func makeSyncEngine(
    database: any DatabaseWriter,
    images: InMemorySyncImageStore = InMemorySyncImageStore(),
    credentials: InMemorySyncCredentialStore = InMemorySyncCredentialStore(deviceToken: "salty_test", deviceId: "device-1")
) -> ServerSyncEngine {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SyncEngineStubURLProtocol.self]
    return ServerSyncEngine(
        database: database,
        session: URLSession(configuration: config),
        credentials: credentials,
        settings: InMemorySyncSettings(),
        images: images,
        deviceName: "Test Device"
    )
}

/// The routes every full sync needs: the token check, device registration (a returning device with
/// a watermark, or a first sync when `lastSync` is nil), completion, and an empty manifest and delta
/// that a test overrides by putting its own routes FIRST (first match wins).
func syncBaseRoutes(lastSync: Date?) -> [SyncEngineStubURLProtocol.Route] {
    let device: String
    if let lastSync {
        device = #"{"isFirstSync": false, "lastSyncDate": "\#(SyncWireDate.string(from: lastSync))"}"#
    } else {
        device = #"{"isFirstSync": true}"#
    }
    return [
        .init("POST", "/api/auth/token/verify", body: #"{"username":"tester"}"#),
        .init("POST", "/api/recipes/sync/device", body: device),
        .init("POST", "/api/recipes/sync/device/", isPrefix: true, body: "{}"),
        .init("GET", "/api/recipes/sync/manifest"),
        .init("GET", "/api/recipes"),
    ]
}

/// Whether the engine told the server the sync finished: the last step, skipped after any throw.
func syncWasCompleted() -> Bool {
    SyncEngineStubURLProtocol.recorded.contains { $0.method == "POST" && $0.path.hasSuffix("/complete") }
}

// MARK: - Wire JSON

/// Encodes with the server's date format (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`), as the engine does.
func wireJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, enc in
        var container = enc.singleValueContainer()
        try container.encode(SyncWireDate.string(from: date))
    }
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

/// Decodes a recorded request body the way the server would.
func wireDecode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = SyncWireDate.date(from: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(text)")
        }
        return date
    }
    return try decoder.decode(type, from: data)
}

/// What the server's manifest lists per recipe. The core's `ServerRecipeManifestEntry` has no public
/// initialiser, so the stub encodes its own shape with the same keys.
struct ManifestEntry: Encodable {
    var id: String
    var lastModifiedDate: Date?
    var imageFilename: String?
    var lastModifiedImageDate: Date?
    var lastPrepared: Date?
    var lastModifiedPreparedDate: Date?
}

func manifestEntry(
    _ id: String, modified: Date, imageFilename: String? = nil, imageDate: Date? = nil,
    lastPrepared: Date? = nil, preparedStamp: Date? = nil
) -> ManifestEntry {
    ManifestEntry(
        id: id, lastModifiedDate: modified, imageFilename: imageFilename, lastModifiedImageDate: imageDate,
        lastPrepared: lastPrepared, lastModifiedPreparedDate: preparedStamp
    )
}

/// A server recipe body. Built through `ServerRecipe.from` because the wire type's memberwise
/// initialiser is not public.
func serverRecipe(
    _ id: String, name: String, modified: Date, courseId: String? = nil,
    lastPrepared: Date? = nil, preparedStamp: Date? = nil
) -> ServerRecipe {
    ServerRecipe.from(Recipe(
        id: id, name: name, lastModifiedDate: modified,
        lastPrepared: lastPrepared, lastModifiedPreparedDate: preparedStamp, courseId: courseId
    ))
}

// MARK: - Seeding and reading rows

/// Fixed instants, an hour apart, already on whole milliseconds.
enum SyncTestClock {
    static let t0 = Date(timeIntervalSince1970: 1_780_000_000)
    static let t1 = t0.addingTimeInterval(3600)
    static let t2 = t0.addingTimeInterval(7200)
    static let t3 = t0.addingTimeInterval(10800)
    static let t4 = t0.addingTimeInterval(14400)
}

/// Stores `recipe` with exactly the stamps and image columns it carries, optionally recording server
/// agreement at its `lastModifiedDate`.
func seedRecipe(_ recipe: Recipe, agreed: Bool = false, in database: any DatabaseWriter) throws {
    try database.write { db in
        try RecipeWriter.save(recipe, in: db, now: recipe.lastModifiedDate)
        try db.execute(
            sql: """
                UPDATE "recipe" SET "imageFilename" = ?, "imageThumbnailData" = ?, "lastModifiedImageDate" = ?,
                    "lastPrepared" = ?, "lastModifiedPreparedDate" = ?, "lastModifiedDate" = ?
                WHERE "id" = ?
                """,
            arguments: [recipe.imageFilename, recipe.imageThumbnailData, recipe.lastModifiedImageDate,
                        recipe.lastPrepared, recipe.lastModifiedPreparedDate, recipe.lastModifiedDate, recipe.id]
        )
        if agreed {
            try RecipeAgreementStore.markAgreed([recipe.id], in: db)
        }
    }
}

func seedClassifier(_ table: String, id: String, name: String, modified: Date, in database: any DatabaseWriter) throws {
    precondition(["category", "course", "tag"].contains(table))
    try database.write { db in
        try db.execute(
            sql: #"INSERT INTO "\#(table)" ("id", "name", "lastModifiedDate") VALUES (?, ?, ?)"#,
            arguments: [id, name, modified]
        )
    }
}

func recipeRow(_ id: String, in database: any DatabaseWriter) throws -> Row? {
    try database.read { db in
        try Row.fetchOne(db, sql: #"SELECT * FROM "recipe" WHERE "id" = ?"#, arguments: [id])
    }
}

func recipeCount(in database: any DatabaseWriter) throws -> Int {
    try database.read { db in
        try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "recipe""#) ?? -1
    }
}

func shoppingListRow(_ id: String, in database: any DatabaseWriter) throws -> Row? {
    try database.read { db in
        try Row.fetchOne(db, sql: #"SELECT * FROM "shoppingList" WHERE "id" = ?"#, arguments: [id])
    }
}

/// The checklist texts stored in a shopping-list row.
func shoppingListTexts(_ row: Row) throws -> [String] {
    let json: String = row["contentsForList"] ?? "[]"
    return try JSONDecoder().decode([ShoppingListListContents].self, from: Data(json.utf8)).map(\.text)
}
