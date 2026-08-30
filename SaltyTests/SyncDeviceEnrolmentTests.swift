//
//  SyncDeviceEnrolmentTests.swift
//  SaltyTests
//
//  The device/token authentication scheme: enrol once with a password, then keep minting short-lived
//  JWTs from the sync token forever after.
//
//  Weighted towards the cases where getting it wrong is expensive and quiet rather than the happy path:
//  a password that survives enrolment, a token thrown away because the server was merely down, and a
//  revoked token that keeps being retried instead of asking the user. The happy path announces itself;
//  these don't.
//
//  Driven through a URLProtocol-stubbed session and an in-memory credential store, so nothing here
//  touches a live server or the developer's keychain. Serialized: the stub and the service's
//  UserDefaults-backed configuration are shared global state.
//

import Testing
import Foundation
@testable import Salty

/// A URLProtocol that routes on path, and -- unlike the other stubs in this target -- keeps each
/// request's body.
///
/// The body matters here: the single most important thing about enrolment is that it sends a
/// `deviceId`, because a server that doesn't see one issues no token and says nothing about it.
/// `URLSession` moves `httpBody` into `httpBodyStream` before a `URLProtocol` sees it, hence the read.
final class AuthRouteStubURLProtocol: URLProtocol {
    struct Response { var status: Int; var body: String }
    struct Recorded {
        let path: String
        let headers: [String: String]
        let body: String
    }

    /// Keyed by path. An unrouted path answers 200 `{}`.
    nonisolated(unsafe) static var responses: [String: Response] = [:]
    nonisolated(unsafe) static var recorded: [Recorded] = []

    static func reset(_ responses: [String: Response] = [:]) {
        self.responses = responses
        recorded = []
    }

    static func request(forPath path: String) -> Recorded? {
        recorded.first { $0.path == path }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.recorded.append(
            Recorded(path: path,
                     headers: request.allHTTPHeaderFields ?? [:],
                     body: Self.bodyString(of: request))
        )

        let response = Self.responses[path] ?? Response(status: 200, body: "{}")
        let url = request.url ?? URL(string: "https://stub.local")!
        if let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil,
                                      headerFields: ["Content-Type": "application/json"]) {
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func bodyString(of request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// The UserDefaults keys `SyncDeviceEnrolmentTests.makeService` writes, and restores afterwards.
private let enrolmentTestManagedDefaultsKeys = [
    "serverUrl", "syncDeviceId", "serverUsername", "serverTokenExpiration",
]

/// A class rather than a struct so `deinit` can put UserDefaults back.
///
/// These tests share a container with the app on whichever simulator runs them, and one of the keys
/// they set is `syncDeviceId`. Leaving a test value there would make a developer's own copy of Salty
/// enrol as a brand-new device on the next sync, stranding its history on the old server-side row --
/// a confusing, entirely self-inflicted bug. Cheap to prevent, so prevent it.
@MainActor
@Suite(.serialized)
final class SyncDeviceEnrolmentTests {

    private static let deviceId = "TEST-DEVICE-0001"

    /// `nonisolated(unsafe)` because `deinit` is nonisolated and `[String: Any]` isn't Sendable. Safe
    /// in fact rather than by assertion: it's a `let`, written once in `init` and read once in `deinit`,
    /// with no window in which anything could mutate or race on it.
    nonisolated(unsafe) private let savedDefaults: [String: Any]

    init() {
        var saved: [String: Any] = [:]
        for key in enrolmentTestManagedDefaultsKeys {
            if let value = UserDefaults.standard.object(forKey: key) { saved[key] = value }
        }
        savedDefaults = saved
    }

    // `deinit` is nonisolated, hence the file-level key list rather than a static on this class.
    deinit {
        for key in enrolmentTestManagedDefaultsKeys {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// A login reply carrying a freshly issued sync token, shaped as the server sends it.
    private static func loginBody(deviceToken: String? = "salty_abc123",
                                  username: String = "cook",
                                  expiresIn: Int = 5_400_000) -> String {
        let tokenField = deviceToken.map { ",\"deviceToken\":\"\($0)\"" } ?? ""
        return """
        {"token":"jwt-from-password","username":"\(username)","expiresIn":\(expiresIn)\(tokenField)}
        """
    }

    /// A `/api/auth/token` reply: a fresh JWT and, correctly, no device token.
    private static func mintBody(jwt: String = "jwt-from-device-token") -> String {
        """
        {"token":"\(jwt)","username":"cook","expiresIn":5400000}
        """
    }

    /// Builds a service wired to the stub, with the given starting credentials.
    ///
    /// `syncDeviceId` is pinned so tests can assert the exact id enrolment sends -- and so they assert
    /// the *existing* sync id is reused rather than a fresh one, which is what keeps one physical
    /// device from appearing twice on the server's devices page.
    private func makeService(
        responses: [String: AuthRouteStubURLProtocol.Response],
        username: String = "cook",
        password: String = "",
        jwtToken: String? = nil,
        deviceToken: String? = nil
    ) -> (SaltySyncService, InMemorySyncCredentialStore) {
        UserDefaults.standard.set("https://stub.local", forKey: "serverUrl")
        UserDefaults.standard.set(Self.deviceId, forKey: "syncDeviceId")
        UserDefaults.standard.set(username, forKey: "serverUsername")
        UserDefaults.standard.removeObject(forKey: "serverTokenExpiration")
        AuthRouteStubURLProtocol.reset(responses)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthRouteStubURLProtocol.self]
        let store = InMemorySyncCredentialStore(password: password, jwtToken: jwtToken,
                                                deviceToken: deviceToken)
        let service = SaltySyncService(session: URLSession(configuration: config), credentials: store)
        return (service, store)
    }

    // MARK: - Enrolment

    /// Enrolment must ask for a token, and must ask under the id sync already uses.
    @Test func enrolmentSendsTheExistingDeviceIdAndStoresTheIssuedToken() async throws {
        let (service, store) = makeService(
            responses: ["/api/auth/login": .init(status: 200, body: Self.loginBody())]
        )

        try await service.enroll(username: "cook", password: "hunter2")

        let sent = try #require(AuthRouteStubURLProtocol.request(forPath: "/api/auth/login"))
        #expect(sent.body.contains("\"deviceId\":\"\(Self.deviceId)\""),
                "without a deviceId the server issues no token and reports nothing: \(sent.body)")
        #expect(sent.body.contains("\"deviceName\""), "the devices page needs something to label the row")

        #expect(store.deviceToken() == "salty_abc123")
        #expect(store.jwtToken() == "jwt-from-password")
        #expect(service.isEnrolled)
    }

    /// The whole point of the scheme: the password is spent, not kept.
    @Test func enrolmentNeverStoresThePassword() async throws {
        let (service, store) = makeService(
            responses: ["/api/auth/login": .init(status: 200, body: Self.loginBody())]
        )

        try await service.enroll(username: "cook", password: "hunter2")

        #expect(store.password().isEmpty, "the password must not survive the request that spent it")
    }

    /// Upgrading from a build that saved the password: it enrols this device, then it goes.
    @Test func enrolmentErasesAPasswordSavedByAnEarlierBuild() async throws {
        let (service, store) = makeService(
            responses: ["/api/auth/login": .init(status: 200, body: Self.loginBody())],
            password: "saved-by-an-old-build"
        )

        try await service.enroll(username: "cook", password: "saved-by-an-old-build")

        #expect(store.password().isEmpty, "the migration is meant to be one-way")
        #expect(store.deviceToken() == "salty_abc123")
    }

    /// A server predating device tokens accepts the login and ignores the deviceId, so the reply looks
    /// successful. Accepting it would leave the app holding a 90-minute JWT it can never renew, and the
    /// user facing a password prompt every 90 minutes with no explanation.
    @Test func aServerThatIssuesNoTokenIsRejectedRatherThanHalfConnected() async {
        let (service, store) = makeService(
            responses: ["/api/auth/login": .init(status: 200, body: Self.loginBody(deviceToken: nil))]
        )

        do {
            try await service.enroll(username: "cook", password: "hunter2")
            Issue.record("expected enrolment against an old server to fail")
        } catch SyncError.enrolmentUnsupported {
            // expected
        } catch {
            Issue.record("expected .enrolmentUnsupported, got \(error)")
        }

        #expect(store.deviceToken() == nil)
        #expect(!service.isEnrolled, "a half-connected device would look fine and never sync")
    }

    @Test func badCredentialsAreReportedAndChangeNothing() async {
        let (service, store) = makeService(
            responses: ["/api/auth/login": .init(status: 401, body: #"{"error":"Invalid username or password"}"#)]
        )

        await #expect(throws: SyncError.self) {
            try await service.enroll(username: "cook", password: "wrong")
        }
        #expect(store.deviceToken() == nil)
    }

    // MARK: - Minting a JWT from the token

    /// The call the app makes for the rest of its life: token in, JWT out, no password anywhere.
    @Test func aStoredTokenMintsAFreshJwtWithoutThePassword() async throws {
        let (service, store) = makeService(
            responses: ["/api/auth/token": .init(status: 200, body: Self.mintBody())],
            password: "",
            deviceToken: "salty_stored"
        )

        try await service.ensureAuthenticated()

        let sent = try #require(AuthRouteStubURLProtocol.request(forPath: "/api/auth/token"))
        #expect(sent.headers["Authorization"] == "Bearer salty_stored")
        #expect(store.jwtToken() == "jwt-from-device-token")
        #expect(AuthRouteStubURLProtocol.request(forPath: "/api/auth/login") == nil,
                "an enrolled device must never hit the password endpoint again")
    }

    /// A valid, unexpired JWT is reused rather than re-minted -- otherwise every sync would spend a
    /// round trip re-authenticating.
    @Test func anUnexpiredJwtIsReusedWithoutContactingTheServer() async throws {
        let (service, _) = makeService(
            responses: ["/api/auth/token": .init(status: 200, body: Self.mintBody())],
            jwtToken: "still-good",
            deviceToken: "salty_stored"
        )
        UserDefaults.standard.set(Date().addingTimeInterval(3600), forKey: "serverTokenExpiration")

        try await service.ensureAuthenticated()

        #expect(AuthRouteStubURLProtocol.recorded.isEmpty, "no request should have been needed")
    }

    /// A revoked token (devices page, or a password change) is dead. Keeping it would retry forever;
    /// the user has to be asked instead.
    @Test func aRevokedTokenIsDiscardedAndEnrolmentIsRequested() async {
        let (service, store) = makeService(
            responses: ["/api/auth/token": .init(status: 401, body: #"{"error":"unauthorized"}"#)],
            deviceToken: "salty_revoked"
        )

        do {
            try await service.ensureAuthenticated()
            Issue.record("expected a revoked token to require enrolment")
        } catch SyncError.enrolmentRequired {
            // expected
        } catch {
            Issue.record("expected .enrolmentRequired, got \(error)")
        }

        #expect(store.deviceToken() == nil, "a dead token must not be retried on every sync")
        #expect(!service.isEnrolled)
    }

    /// The mirror case, and the more damaging one to get wrong: the server being down says nothing
    /// about the token. Discarding it here would cost a password prompt for what is a network blip.
    @Test func aServerOutageLeavesTheTokenInPlace() async {
        let (service, store) = makeService(
            responses: ["/api/auth/token": .init(status: 503, body: #"{"error":"maintenance"}"#)],
            deviceToken: "salty_stored"
        )

        do {
            try await service.ensureAuthenticated()
            Issue.record("expected the outage to surface as an error")
        } catch SyncError.enrolmentRequired {
            Issue.record("a 503 must not be read as revocation")
        } catch {
            // expected: an authentication/network failure, token untouched
        }

        #expect(store.deviceToken() == "salty_stored", "the token is very probably still good")
        #expect(service.isEnrolled)
    }

    // MARK: - Migration and the un-enrolled state

    /// Existing installs upgrade without ever seeing the prompt: the password they already saved is
    /// good for exactly one more login, and that login is the one that enrols them.
    @Test func aSavedPasswordEnrolsSilentlyOnTheNextSync() async throws {
        let (service, store) = makeService(
            responses: ["/api/auth/login": .init(status: 200, body: Self.loginBody())],
            password: "saved-by-an-old-build"
        )
        #expect(service.hasCredentials, "a saved password should still count as able to sync")
        #expect(!service.isEnrolled)

        try await service.ensureAuthenticated()

        #expect(store.deviceToken() == "salty_abc123")
        #expect(store.password().isEmpty)
        #expect(service.isEnrolled, "the upgrade should complete without ever prompting")
    }

    @Test func withNoTokenAndNoPasswordTheUserMustBeAsked() async {
        let (service, _) = makeService(responses: [:], password: "")

        do {
            try await service.ensureAuthenticated()
            Issue.record("expected enrolment to be required")
        } catch SyncError.enrolmentRequired {
            // expected
        } catch {
            Issue.record("expected .enrolmentRequired, got \(error)")
        }
        #expect(!service.hasCredentials)
    }

    // MARK: - Forgetting the device

    /// Signing out ends the token's life on the server too, so a forgotten device is actually
    /// forgotten rather than merely stopping locally while a live credential sits on the server.
    @Test func forgettingRevokesTheTokenOnTheServerThenClearsIt() async throws {
        let (service, store) = makeService(
            responses: ["/api/auth/token/revoke": .init(status: 204, body: "")],
            password: "leftover", jwtToken: "cached", deviceToken: "salty_stored"
        )

        let outcome = await service.signOut()

        let sent = try #require(AuthRouteStubURLProtocol.request(forPath: "/api/auth/token/revoke"))
        #expect(sent.headers["Authorization"] == "Bearer salty_stored",
                "the revoke has to present the very token it is retiring")
        #expect(outcome == .revokedOnServer)
        #expect(store.deviceToken() == nil)
        #expect(store.jwtToken() == nil)
        #expect(store.password().isEmpty)
        #expect(!service.hasCredentials)
    }

    /// The user asked to sign out. A server that can't be reached must not be able to keep them
    /// signed in -- it may report that the job is half done, and nothing more.
    @Test func forgettingClearsLocallyEvenWhenTheServerRefuses() async {
        let (service, store) = makeService(
            responses: ["/api/auth/token/revoke": .init(status: 503, body: #"{"error":"down"}"#)],
            deviceToken: "salty_stored"
        )

        let outcome = await service.signOut()

        #expect(outcome == .localOnly, "the caller needs to know it can't promise the token is dead")
        #expect(store.deviceToken() == nil, "signing out must still succeed on this device")
        #expect(!service.isEnrolled)
    }

    /// A token the server has already revoked (devices page, or a password change) is exactly the
    /// state we wanted. Reporting that as a failure would send the user chasing a problem they don't
    /// have.
    @Test func aTokenTheServerHasAlreadyRevokedCountsAsRevoked() async {
        let (service, _) = makeService(
            responses: ["/api/auth/token/revoke": .init(status: 401, body: #"{"error":"unauthorized"}"#)],
            deviceToken: "salty_already_dead"
        )

        let outcome = await service.signOut()

        #expect(outcome == .revokedOnServer)
    }
}
