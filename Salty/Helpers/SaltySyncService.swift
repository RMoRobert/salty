//
//  SaltySyncService.swift
//  Salty
//
//  Created by Robert on 1/24/26.

//  The app's side of sync: observable state for Settings, the sync footer and menus, and the checks on
//  whether a sync may run. The sync itself is SaltyCore's `ServerSyncEngine`; this class supplies it with
//  the app's database, Keychain, settings and image files, and mirrors its progress onto the main actor.
//

import Foundation
import SQLiteData
import OSLog
import SaltyCore
#if canImport(UIKit)
import UIKit   // sole use: UIDevice.current.name in `deviceName` (macOS uses Foundation's Host)
#endif

// MARK: - Sync Service

@MainActor
@Observable
class SaltySyncService {
    static let shared = SaltySyncService()

    private let logger = Logger(subsystem: "Salty", category: "Sync")

    /// URLSession used for all server calls. Defaults to `.shared`; injectable so tests can stub responses
    /// (e.g. a `URLProtocol`-backed session) and exercise the error paths without a live server.
    @ObservationIgnored
    private let session: URLSession

    /// Storage for the device sync token. Defaults to the keychain; injectable so tests can run
    /// against an in-memory store instead of the developer's own keychain.
    @ObservationIgnored
    private let credentials: any SyncCredentialStore

    @ObservationIgnored
    private let settings = UserDefaultsSyncSettings()

    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database

    var isSyncing = false

    /// When the last sync finished successfully. Persisted (see `lastSyncDateKey`) so the Settings screen
    /// can still show it after a relaunch; `nil` only until the first successful sync on this device.
    var lastSyncDate: Date? {
        didSet { UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncDateKey) }
    }
    private static let lastSyncDateKey = "lastSuccessfulSyncDate"

    var lastSyncError: String?
    var syncProgress: SyncProgress = SyncProgress()

    /// The in-flight cancellable sync, if any. Only `syncNow()` registers here: the force re-sync paths
    /// deliberately stay non-cancellable because they wipe one side before repopulating it, so stopping
    /// partway would leave a half-populated library with no way back but re-running.
    @ObservationIgnored
    private var currentSyncTask: Task<Void, Error>?

    /// The engine running the current operation, so a cancel can tell it to say so.
    @ObservationIgnored
    private var currentEngine: ServerSyncEngine?

    /// True between the user asking to cancel and the sync unwinding. Drives the "Cancelling…" button state.
    private(set) var isCancelling = false

    /// Whether the sync currently running can be cancelled. False when idle, and false during a force re-sync.
    var isCancellable: Bool { currentSyncTask != nil }

    private var serverUrl: String {
        settings.serverURL()
    }

    private var serverEnabled: Bool {
        UserDefaults.standard.bool(forKey: "serverUse")
    }

    // MARK: - Authentication Properties

    /// Username for server authentication
    var serverUsername: String {
        get { settings.username() }
        set { settings.setUsername(newValue) }
    }

    /// Whether this device holds a sync token, and so can sync without asking the user for anything.
    ///
    /// Stored rather than computed from the keychain on demand, for two reasons. It is read from SwiftUI
    /// `body` -- once per keystroke while the password field has focus -- and a keychain round trip per
    /// render is waste. More importantly it has to be *observable*: computing it through
    /// `@ObservationIgnored` storage would leave Settings showing the disconnected form after a
    /// successful connect, until some unrelated state change happened to redraw it. The keychain remains
    /// the source of truth; this mirrors it, refreshed by `withEngine` after every engine operation. Reach
    /// the engine only through `withEngine`, or a token change can leave the UI showing the old state.
    private(set) var isEnrolled: Bool

    /// Whether a password saved by a pre-enrolment build is still waiting to be spent on enrolment.
    /// Same reasoning as `isEnrolled`: read from `body`, and has to change visibly when it's consumed.
    private(set) var hasUnspentSavedPassword: Bool

    /// Whether a sync can authenticate unattended.
    ///
    /// True once enrolled, and also while a password saved by a pre-enrolment build is still sitting in
    /// the keychain -- that password is spent enrolling this device on the next sync and then deleted, so
    /// upgrading users are never prompted. See `ServerSyncEngine.ensureAuthenticated()`.
    var hasCredentials: Bool {
        isEnrolled || (!serverUsername.isEmpty && hasUnspentSavedPassword)
    }

    /// Device name for display purposes
    private var deviceName: String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown Device"
        #endif
    }

    /// `session` defaults to `.shared` and `credentials` to the keychain, as the app singleton needs;
    /// tests inject a stubbed session and an in-memory credential store.
    init(session: URLSession = .shared, credentials: any SyncCredentialStore = KeychainHelper.shared) {
        self.session = session
        self.credentials = credentials
        // The only two keychain reads on this path: everything afterwards works off these mirrors.
        isEnrolled = !(credentials.deviceToken() ?? "").isEmpty
        hasUnspentSavedPassword = !credentials.password().isEmpty
        // Restore the last sync time from a previous run. Assignment in `init` doesn't fire `didSet`, so
        // this doesn't write the value straight back.
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncDateKey) as? Date
    }

    /// Re-reads the two credential mirrors after the engine may have changed them.
    private func refreshCredentialState() {
        let enrolled = !(credentials.deviceToken() ?? "").isEmpty
        if enrolled != isEnrolled { isEnrolled = enrolled }
        let unspent = !credentials.password().isEmpty
        if unspent != hasUnspentSavedPassword { hasUnspentSavedPassword = unspent }
    }

    // MARK: - Engine

    /// Runs one operation on a fresh `ServerSyncEngine` wired to this app, mirroring its progress into
    /// `syncProgress` and its credential changes into `isEnrolled`/`hasUnspentSavedPassword`.
    ///
    /// Progress arrives through a stream so updates land on the main actor in the order the engine made
    /// them, and the stream is drained before this returns, so `syncProgress` already shows how the
    /// operation ended.
    private func withEngine<T: Sendable>(_ operation: @Sendable (ServerSyncEngine) async throws -> T) async rethrows -> T {
        let (updates, continuation) = AsyncStream.makeStream(of: SyncProgress.self)
        // The dependency itself rather than its value: the engine resolves it only if the operation
        // reads the library, which enrolment and sign-out never do (so their tests need no database).
        let database = _database
        let engine = ServerSyncEngine(
            database: database.wrappedValue,
            session: session,
            credentials: credentials,
            settings: settings,
            images: RecipeImageManager.shared,
            deviceName: deviceName,
            prepareImage: { await SyncImagePreparer.prepare($0) },
            // A list open in a checklist/freeform editor is held in memory; without this, its next
            // keystroke would save the pre-sync content straight back over what was downloaded.
            shoppingListChanged: { id in await ShoppingListChangeNotifier.shared.noteExternalChange(listId: id) },
            onProgress: { continuation.yield($0) }
        )
        let observer = Task {
            for await update in updates {
                syncProgress = update
            }
        }
        currentEngine = engine
        defer {
            currentEngine = nil
            refreshCredentialState()
        }
        do {
            let result = try await operation(engine)
            continuation.finish()
            await observer.value
            return result
        } catch {
            continuation.finish()
            await observer.value
            throw error
        }
    }

    // MARK: - Authentication Methods

    /// Enrols this device: the one and only time the password is needed. See `ServerSyncEngine.enroll`.
    func enroll(username: String, password: String) async throws {
        try await withEngine { try await $0.enroll(username: username, password: password) }
    }

    /// Makes sure this device holds a credential the server still accepts. See
    /// `ServerSyncEngine.ensureAuthenticated`; internal rather than private so the auth paths can be tested.
    func ensureAuthenticated() async throws {
        try await withEngine { try await $0.ensureAuthenticated() }
    }

    typealias ForgetOutcome = SyncForgetOutcome

    /// Forgets this device: revokes its token on the server, then discards it here, so the next sync
    /// asks for the password again. See `ServerSyncEngine.signOut`.
    @discardableResult
    func signOut() async -> ForgetOutcome {
        await withEngine { await $0.signOut() }
    }

    // MARK: - Public Sync Methods

    /// How soon after a successful sync another may start. See `ServerSyncEngine.minimumSyncInterval`.
    nonisolated static let minimumSyncInterval: TimeInterval = ServerSyncEngine.minimumSyncInterval

    /// Whether a new sync should be skipped because one finished moments ago. See
    /// `ServerSyncEngine.shouldThrottleSync`.
    nonisolated static func shouldThrottleSync(lastSuccessfulSync: Date?, now: Date = Date(), force: Bool) -> Bool {
        ServerSyncEngine.shouldThrottleSync(lastSuccessfulSync: lastSuccessfulSync, now: now, force: force)
    }

    /// Performs a full bidirectional sync with the server.
    ///
    /// The steps run in their own task, registered as `currentSyncTask`, so `cancelSync()` can stop a sync
    /// no matter which caller started it (Settings' "Sync Now", auto-sync, or the failure banner's Retry).
    /// Cancelling is safe at any point; see `ServerSyncEngine.sync()`.
    /// `force` skips the recently-synced guard (Settings' own Sync Now uses it); every other trigger --
    /// auto-sync, pull-to-refresh, the sync footer, the menu command -- accepts a `.throttled` skip when a
    /// sync finished within the last `minimumSyncInterval`, so stacked triggers can't hammer the server.
    func syncNow(force: Bool = false) async throws {
        guard serverEnabled else {
            throw SyncError.serverNotConfigured
        }

        guard !serverUrl.isEmpty else {
            throw SyncError.serverNotConfigured
        }

        guard hasCredentials else {
            throw SyncError.credentialsNotConfigured
        }

        guard !isSyncing else {
            logger.warning("Sync already in progress, skipping")
            return
        }

        if Self.shouldThrottleSync(lastSuccessfulSync: lastSyncDate, force: force) {
            logger.info("Sync skipped: a sync finished within the last \(Int(Self.minimumSyncInterval))s")
            throw SyncError.throttled
        }

        // Claim the slot synchronously -- we're on the main actor and haven't suspended yet, so no second
        // caller can slip past the guard above before the task below starts running.
        isSyncing = true
        isCancelling = false
        lastSyncError = nil
        syncProgress = SyncProgress()

        let task = Task { @MainActor in
            try await self.performFullSync()
        }
        currentSyncTask = task

        defer {
            currentSyncTask = nil
            isCancelling = false
            isSyncing = false
        }

        // `Task {}` is unstructured, so cancelling *our* caller wouldn't reach it on its own; forward it.
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Stops the sync in progress, if it's one of the cancellable ones (`syncNow()`; never a force re-sync).
    /// Cancellation lands at the next suspension point, which in practice is the current network request.
    func cancelSync() {
        guard let currentSyncTask else { return }
        guard !isCancelling else { return }
        logger.info("Sync cancellation requested during '\(self.syncProgress.currentStep)'")
        isCancelling = true
        syncProgress.currentStep = "Cancelling..."
        if let currentEngine {
            // The engine owns the progress display, so it has to be the one to say "Cancelling...".
            // Told before the cancel, so the "Sync cancelled" it sets while unwinding can't be overtaken.
            Task {
                await currentEngine.noteCancelling()
                currentSyncTask.cancel()
            }
        } else {
            currentSyncTask.cancel()
        }
    }

    /// `syncNow()` owns the `isSyncing`/cancellation bookkeeping around this.
    private func performFullSync() async throws {
        do {
            try await withEngine { try await $0.sync() }
            lastSyncDate = Date()
        } catch {
            // A cancel is a user action, not a failure to report.
            lastSyncError = SyncError.isCancellation(error) ? nil : friendlySyncMessage(error)
            throw error
        }
    }

    /// Force a full re-sync: delete *all* local recipes/courses/categories/tags and re-download
    /// everything from the server. See `ServerSyncEngine.forceFullResyncFromServer`.
    func forceFullResyncFromServer() async throws {
        guard serverEnabled, !serverUrl.isEmpty else { throw SyncError.serverNotConfigured }
        guard hasCredentials else { throw SyncError.credentialsNotConfigured }
        guard !isSyncing else {
            logger.warning("Sync already in progress, skipping force re-sync")
            return
        }

        isSyncing = true
        lastSyncError = nil
        syncProgress = SyncProgress()
        defer { isSyncing = false }

        do {
            try await withEngine { try await $0.forceFullResyncFromServer() }
            lastSyncDate = Date()
        } catch {
            lastSyncError = friendlySyncMessage(error)
            throw error
        }
    }

    /// Force a full re-sync in the opposite direction: make the server an exact mirror of this
    /// device. See `ServerSyncEngine.forceFullResyncToServer`.
    func forceFullResyncToServer() async throws {
        guard serverEnabled, !serverUrl.isEmpty else { throw SyncError.serverNotConfigured }
        guard hasCredentials else { throw SyncError.credentialsNotConfigured }
        guard !isSyncing else {
            logger.warning("Sync already in progress, skipping force re-sync")
            return
        }

        isSyncing = true
        lastSyncError = nil
        syncProgress = SyncProgress()
        defer { isSyncing = false }

        do {
            try await withEngine { try await $0.forceFullResyncToServer() }
            lastSyncDate = Date()
        } catch {
            lastSyncError = friendlySyncMessage(error)
            throw error
        }
    }

    // MARK: - Individual requests (unit-tested through this class)

    /// Mark sync as complete on server. See `ServerSyncEngine.completeSyncOnServer`.
    func completeSyncOnServer() async throws {
        try await withEngine { try await $0.completeSyncOnServer() }
    }

    /// Delete recipes on the server. See `ServerSyncEngine.deleteRecipesOnServer`.
    func deleteRecipesOnServer(recipeIds: [String]) async throws {
        try await withEngine { try await $0.deleteRecipesOnServer(recipeIds: recipeIds) }
    }

    /// Downloads one image into the library. See `ServerSyncEngine.downloadImage`.
    func downloadImage(filename: String, for recipeId: String, imageDate: Date?,
                       maxBytes: Int = ServerSyncEngine.maxImageDownloadBytes) async throws {
        try await withEngine {
            try await $0.downloadImage(filename: filename, for: recipeId, imageDate: imageDate, maxBytes: maxBytes)
        }
    }

    /// See `ServerSyncEngine.encodedImagePathComponent`.
    nonisolated static func encodedImagePathComponent(_ filename: String) -> String? {
        ServerSyncEngine.encodedImagePathComponent(filename)
    }

    /// See `ServerSyncEngine.forceWriteHeader`.
    nonisolated static let forceWriteHeader = ServerSyncEngine.forceWriteHeader
}
