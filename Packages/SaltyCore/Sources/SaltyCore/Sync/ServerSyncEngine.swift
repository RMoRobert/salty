//
//  ServerSyncEngine.swift
//  SaltyCore
//
//  Bidirectional sync between a Salty library and Salty Server: enrolment, the sync passes, the two
//  force re-syncs, and the HTTP they need. Shared by every client; the Apple app wraps it in
//  SaltySyncService.
//
//  Nothing here may touch the main actor: a non-Swift host (a .NET client calling in through
//  SaltyCoreFFI) never runs the main queue, so anything waiting on it would wait forever.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GRDB
import SQLiteData
import UUIDV7

// MARK: - Sync Engine

/// Runs sync operations against one library. Cheap to create; the Apple app makes one per operation.
///
/// An actor because its progress is mutable state shared with whoever observes it. The work itself is
/// mostly awaiting the network and GRDB, so the actor is free between requests.
public actor ServerSyncEngine {

    private let logger = SaltyLogger(subsystem: "Salty", category: "Sync")

    /// Resolved on first use, so an operation that never reads the library (enrolment, sign-out, one
    /// of the single requests) never opens it.
    private let resolveDatabase: @Sendable () -> any DatabaseWriter
    private lazy var database: any DatabaseWriter = resolveDatabase()
    private let session: URLSession
    private let credentials: any SyncCredentialStore
    private let settings: any SyncSettingsStore
    private let images: any SyncImageStore
    private let deviceName: String
    private let prepareImage: @Sendable (Data) async -> PreparedSyncImage
    private let shoppingListChanged: @Sendable (String) async -> Void
    private let onProgress: @Sendable (SyncProgress) -> Void

    /// What the current operation is doing. Every change is also passed to the `onProgress` callback, in
    /// order, on the engine's executor.
    public private(set) var progress = SyncProgress() {
        didSet { onProgress(progress) }
    }

    /// - Parameters:
    ///   - database: The library's database. Evaluated the first time an operation needs it, not here.
    ///   - deviceName: How this device is labelled on the server's devices page, and in the name of a
    ///     shopping list's conflicted copy.
    ///   - prepareImage: Readies an image for upload. The default only labels PNG/JPEG/GIF/WebP by their
    ///     header; the Apple app converts HEIC and WebP (`SyncImagePreparer`).
    ///   - shoppingListChanged: Called after sync writes or deletes a shopping list locally, so an editor
    ///     holding that list in memory reloads instead of saving its stale copy back.
    ///   - onProgress: Called with every change to `progress`. Synchronous and on the engine's executor,
    ///     so keep it short: hand the value to whatever displays it.
    public init(
        database: @autoclosure @escaping @Sendable () -> any DatabaseWriter,
        session: URLSession = .shared,
        credentials: any SyncCredentialStore,
        settings: any SyncSettingsStore,
        images: any SyncImageStore,
        deviceName: String,
        prepareImage: @escaping @Sendable (Data) async -> PreparedSyncImage = { PreparedSyncImage.passThrough($0) },
        shoppingListChanged: @escaping @Sendable (String) async -> Void = { _ in },
        onProgress: @escaping @Sendable (SyncProgress) -> Void = { _ in }
    ) {
        self.resolveDatabase = database
        self.session = session
        self.credentials = credentials
        self.settings = settings
        self.images = images
        self.deviceName = deviceName
        self.prepareImage = prepareImage
        self.shoppingListChanged = shoppingListChanged
        self.onProgress = onProgress
    }

    private var serverUrl: String {
        settings.serverURL()
    }

    // MARK: - Authentication Properties

    /// Username for server authentication
    private var serverUsername: String {
        get { settings.username() }
        set { settings.setUsername(newValue) }
    }

    /// The per-device sync token the server issued when this device enrolled.
    ///
    /// This is the app's only lasting credential, and it is deliberately weaker than the password it
    /// replaces: the server accepts it on the sync routes and nowhere else, so a copy lifted off this
    /// device can read and write recipes but cannot change the account password or revoke any other
    /// device. `nil` means this device is not enrolled and a sync must ask for the password once.
    private var deviceToken: String? {
        get { credentials.deviceToken() }
        set { credentials.setDeviceToken(newValue) }
    }

    /// Whether this device holds a sync token, and so can sync without asking the user for anything.
    private var isEnrolled: Bool {
        !(deviceToken ?? "").isEmpty
    }

    /// Erases a migrated legacy password.
    private func discardSavedPassword() {
        credentials.setPassword("")
    }

    /// Unique device ID for sync tracking (generated once, persisted).
    ///
    /// Kept in the credential store beside the token, but unlike the token it is *portable*: it follows
    /// an encrypted backup or device transfer, so a replacement phone carries on as the same device
    /// and keeps its sync history. The token does not follow, so the restored phone asks for the
    /// password once and re-enrols under this id -- which supersedes the previous phone's token
    /// server-side (one token per device id). That supersession is what keeps two live devices from
    /// quietly sharing one server-side watermark: the old phone is signed out and has to be
    /// reconnected deliberately.
    private var deviceId: String {
        if let existing = credentials.deviceId(), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        credentials.setDeviceId(newId)
        logger.info("Generated new device ID: \(newId)")
        return newId
    }

    /// Cap on image bytes accepted from the sync server, so a hostile/misbehaving server can't make a
    /// sync balloon memory or disk. Deliberately larger than the app's own import cap: a server image
    /// can legitimately exceed it because uploads are converted before sending (HEIC → PNG can inflate
    /// several-fold) and other clients may apply different limits.
    public static let maxImageDownloadBytes = 250 * 1024 * 1024   // 250 MB

    /// Updates the progress text to show a cancel is underway. The cancel itself is the caller
    /// cancelling the operation's task.
    public func noteCancelling() {
        progress.currentStep = "Cancelling..."
    }

    // MARK: - Authentication Methods
    
    /// The server's reply to `/api/auth/login` and `/api/auth/token/verify`.
    ///
    /// `deviceToken` is present exactly once, in the login that enrols this device, and only because we
    /// asked by sending a `deviceId`. The verify call omits it -- we are already holding it.
    /// The device token itself authenticates every sync route, so there is no session token to decode.
    private struct AuthResponse: Decodable {
        let username: String
        let deviceToken: String?
    }

    /// Enrols this device: the one and only time the password is needed.
    ///
    /// Sends the password with this device's `deviceId`, and the server returns a long-lived sync token.
    /// The password is used for this single request and never written anywhere -- not to the keychain,
    /// not to a stored property. From here on that token is the credential every request carries.
    ///
    /// The `deviceId` deliberately reuses the one the sync protocol already registers under: the server
    /// keys tokens on (user, deviceId), so enrolling under a fresh id would list this device twice on the
    /// server's devices page and strand its sync history on the old row.
    public func enroll(username: String, password: String) async throws {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else {
            throw SyncError.authenticationFailed("Username and password are required")
        }

        guard let url = URL(string: "\(serverUrl)/api/auth/login") else {
            throw SyncError.authenticationFailed("Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct EnrolmentRequest: Encodable {
            let username: String
            let password: String
            let deviceId: String
            let deviceName: String
        }
        request.httpBody = try JSONEncoder().encode(
            EnrolmentRequest(username: username, password: password,
                             deviceId: deviceId, deviceName: deviceName)
        )

        logger.info("Enrolling device for user: \(username)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.authenticationFailed("Invalid response from server")
        }

        if httpResponse.statusCode == 401 {
            throw SyncError.authenticationFailed("Invalid username or password")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            logger.error("Enrolment failed HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
            throw SyncError.authenticationFailed(SyncError.httpMessage(status: httpResponse.statusCode, body: data))
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)

        // A server predating device tokens answers a login unchanged, ignoring the deviceId it doesn't
        // know about. There is no longer any fallback to fall back TO -- the app keeps no other
        // credential -- so this is a setup failure with a message naming the actual fix.
        guard let issuedDeviceToken = authResponse.deviceToken, !issuedDeviceToken.isEmpty else {
            logger.error("Server accepted the login but issued no device token")
            throw SyncError.enrolmentUnsupported
        }

        serverUsername = authResponse.username
        deviceToken = issuedDeviceToken

        // Nothing else in the app writes this key any more; clearing it here is what makes the upgrade
        // from a password-saving build a one-way trip.
        discardSavedPassword()

        logger.info("Device enrolled for user: \(authResponse.username)")
    }

    /// Confirms this device's sync token is still good before a sync leans on it.
    ///
    /// The round trip separates "the server disowned this device" from "the network is down" *before*
    /// a sync starts writing.
    ///
    /// A 401 here is meaningful rather than transient: the token was revoked from the server's devices
    /// page, or the account password changed (which signs every device out). Either way the token is
    /// dead, so it's deleted and the caller is told to enrol again.
    private func verifyDeviceToken() async throws {
        guard let token = deviceToken, !token.isEmpty else {
            throw SyncError.enrolmentRequired
        }
        guard let url = URL(string: "\(serverUrl)/api/auth/token/verify") else {
            throw SyncError.authenticationFailed("Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.authenticationFailed("Invalid response from server")
        }

        // Only a verdict from Salty Server itself may kill the token. A 401 is always that. A 403 is
        // only that when the body is the server's JSON: NGINX access lists answer 403 with an HTML page,
        // and a user who has simply left the home network must not be silently un-enrolled by it.
        let statusCode = httpResponse.statusCode
        if statusCode == 401 || (statusCode == 403 && SyncError.bodyIsServerJSON(data)) {
            logger.warning("Device token rejected (HTTP \(statusCode)); clearing it")
            deviceToken = nil
            throw SyncError.enrolmentRequired
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Anything else -- server down, proxy in the way -- leaves the token alone: it is very
            // probably still good, and discarding it would cost the user a password prompt for what is
            // really a network problem.
            logger.error("Token check failed HTTP \(httpResponse.statusCode)")
            throw SyncError.authenticationFailed(SyncError.httpMessage(status: httpResponse.statusCode, body: data))
        }

        let verified = try JSONDecoder().decode(AuthResponse.self, from: data)
        // The server is the authority on which account the token belongs to, so take the name from it:
        // it is what the Settings screen shows, and it would otherwise drift after a rename.
        serverUsername = verified.username
        logger.info("Device token verified for user: \(verified.username)")
    }

    /// Spends a password left by a pre-enrolment build to enrol this device, once.
    ///
    /// Existing installs upgrade without ever seeing the prompt: the password they already saved is
    /// good for exactly one more login, which is the one that enrols them. `enroll` deletes it on
    /// success. A failure leaves it in place so the next sync can retry.
    private func enrollUsingSavedPassword() async throws {
        let saved = credentials.password()
        guard !saved.isEmpty, !serverUsername.isEmpty else { throw SyncError.enrolmentRequired }
        logger.info("Migrating a saved password into a device token")
        try await enroll(username: serverUsername, password: saved)
    }

    /// Makes sure this device holds a credential the server still accepts, before a sync uses it.
    ///
    /// The device token does not expire, so what matters is whether it is still *accepted*, which only
    /// the server knows and one call establishes.
    ///
    /// Public so the auth paths can be unit-tested without driving a whole sync.
    public func ensureAuthenticated() async throws {
        if isEnrolled {
            try await verifyDeviceToken()
            return
        }

        // Not enrolled. Either this install predates device tokens and still has a saved password to
        // spend, or the user has to be asked for one.
        try await enrollUsingSavedPassword()
    }

    /// Forgets this device: revokes its token on the server, then discards it here, so the
    /// next sync asks for the password again.
    ///
    /// The revoke is attempted first, because it needs the credential this is about to destroy. Local
    /// state is cleared regardless of how it goes: a user who asked to sign out has signed out, and
    /// leaving them connected because a server was unreachable would be the wrong way to fail.
    ///
    /// There is deliberately no "clear just the cached token" counterpart. There is nothing cached to
    /// clear: the device token is the only credential the app holds, and discarding it *is* signing out.
    @discardableResult
    public func signOut() async -> SyncForgetOutcome {
        let outcome = await revokeDeviceTokenOnServer()
        deviceToken = nil
        discardSavedPassword()
        logger.info("Forgot this device (server revoke: \(outcome == .revokedOnServer ? "done" : "unreachable"))")
        return outcome
    }

    /// Asks the server to revoke this device's own token.
    ///
    /// `/api/auth/token/revoke` takes no device id -- it can only revoke whichever device presented the
    /// token, which is why a sync credential is allowed to call it at all while the devices routes stay
    /// behind a password. Revoking oneself is de-escalation; revoking anyone else is not.
    ///
    /// Never throws: this runs on the way out, and no failure here should be able to strand the user on
    /// a device they've asked to sign out of.
    private func revokeDeviceTokenOnServer() async -> SyncForgetOutcome {
        guard let token = deviceToken, !token.isEmpty,
              let url = URL(string: "\(serverUrl)/api/auth/token/revoke") else {
            return .localOnly
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Well under URLSession's 60s default: signing out must not appear to hang because the server
        // is off, and the local half of the job succeeds either way.
        request.timeoutInterval = 15

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .localOnly }
            // 401 means the token was already dead -- revoked from the devices page, or invalidated by
            // a password change. The point of the call is met, so don't alarm the user about it.
            if (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 401 {
                return .revokedOnServer
            }
            logger.warning("Server refused the self-revoke (HTTP \(httpResponse.statusCode))")
            return .localOnly
        } catch {
            logger.warning("Couldn't reach the server to revoke this device: \(error.localizedDescription)")
            return .localOnly
        }
    }

    /// Signs a request with this device's sync token.
    ///
    /// The same credential that authenticates enrolment-adjacent calls now authenticates every sync
    /// request, because the server accepts it directly on the sync routes. It reaches nothing else:
    /// account and device-management routes do not mount the provider that understands it.
    private func addAuthHeader(to request: inout URLRequest) {
        if let token = deviceToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    // MARK: - Public Sync Methods
    
    /// How soon after a successful sync another may start. Short enough that a deliberate re-sync never
    /// feels blocked (and Settings' Sync Now bypasses it entirely), long enough that a pull-to-refresh
    /// landing on top of an automatic sync, or an accidental double-trigger, costs the server nothing.
    public static let minimumSyncInterval: TimeInterval = 30

    /// Whether a new sync should be skipped because one finished moments ago. Pure and injectable (`now`)
    /// so the boundaries are unit-testable. A negative elapsed time means the clock moved backwards
    /// (time zone change, manual clock edit); sync rather than refuse based on a nonsense interval.
    public static func shouldThrottleSync(lastSuccessfulSync: Date?, now: Date = Date(), force: Bool) -> Bool {
        guard !force, let lastSuccessfulSync else { return false }
        let elapsed = now.timeIntervalSince(lastSuccessfulSync)
        return elapsed >= 0 && elapsed < minimumSyncInterval
    }

    /// Checks that the server answers and this device's credentials work, without moving any data:
    /// authenticates and registers the device, the first two things every sync does. Returns when this
    /// device last finished a sync, or nil if it never has.
    public func checkConnection() async throws -> Date? {
        try await ensureAuthenticated()
        let info = try await registerDevice()
        return info.isFirstSync ? nil : info.lastSyncDate
    }

    /// Runs one full bidirectional sync.
    ///
    /// Cancelling the task that runs it is safe at any point: each transfer is individually atomic (one
    /// request per recipe/image, one transaction per local write) and the server only advances this
    /// device's last-sync timestamp in the final `completeSyncOnServer()`, so a cancelled sync just
    /// leaves the rest for the next run. A cancel surfaces as `SyncError.cancelled`.
    ///
    /// Guarding against a second concurrent sync, throttling, and recording when the last one succeeded
    /// are the caller's job.
    public func sync() async throws {
        progress = SyncProgress()
        try await performFullSync()
    }

    private func performFullSync() async throws {
        do {
            // Step 0: Authenticate with server
            logger.info("Step 0: Authenticating...")
            progress.currentStep = "Authenticating..."
            try await ensureAuthenticated()
            logger.info("Authentication successful")
            
            // Step 1: Register device with server
            logger.info("Step 1: Registering device...")
            progress.currentStep = "Registering device..."
            let deviceInfo = try await registerDevice()
            logger.info("Device registered: \(self.deviceId), isFirstSync: \(deviceInfo.isFirstSync)")
            
            // Step 2: Sync courses (with deletion detection)
            logger.info("Step 2: Syncing courses...")
            progress.currentStep = "Syncing courses..."
            try await syncCoursesWithDeletions(deviceInfo: deviceInfo)
            logger.info("Courses synced successfully")
            
            // Step 3: Sync categories (with deletion detection)
            logger.info("Step 3: Syncing categories...")
            progress.currentStep = "Syncing categories..."
            try await syncCategoriesWithDeletions(deviceInfo: deviceInfo)
            logger.info("Categories synced successfully")
            
            // Step 4: Sync tags (with deletion detection)
            logger.info("Step 4: Syncing tags...")
            progress.currentStep = "Syncing tags..."
            try await syncTagsWithDeletions(deviceInfo: deviceInfo)
            logger.info("Tags synced successfully")
            
            // Step 4b: Sync shopping lists (with deletion detection)
            logger.info("Step 4b: Syncing shopping lists...")
            progress.currentStep = "Syncing shopping lists..."
            try await syncShoppingListsWithDeletions(deviceInfo: deviceInfo)
            logger.info("Shopping lists synced successfully")

            // Step 5: Sync recipes (with deletion detection)
            logger.info("Step 5: Syncing recipes...")
            progress.currentStep = "Syncing recipes..."
            try await syncRecipesWithDeletions(deviceInfo: deviceInfo)
            logger.info("Recipes synced successfully")
            
            // Step 6: Sync images
            logger.info("Step 6: Syncing images...")
            progress.currentStep = "Syncing images..."
            try await syncImages()
            logger.info("Images synced successfully")

            // Step 6b: fold any same-named courses/categories/tags into one row
            progress.currentStep = "Tidying categories, courses, and tags..."
            await consolidateDuplicateLibraryItems()

            // Step 7: Mark sync complete on server. Explicitly checked first: completing marks this device
            // caught up, so it must never run after a cancel that skipped work (step 6b doesn't throw).
            try Task.checkCancellation()
            logger.info("Step 7: Completing sync...")
            progress.currentStep = "Completing sync..."
            try await completeSyncOnServer()
            logger.info("Sync marked complete on server")

            progress.currentStep = "Sync complete!"
            logger.info("Sync completed successfully")

        } catch {
            if SyncError.isCancellation(error) {
                logger.info("Sync cancelled at step '\(self.progress.currentStep)'")
                progress.currentStep = "Sync cancelled"
                throw SyncError.cancelled
            }
            logger.error("Sync failed at step '\(self.progress.currentStep)': \(error)")
            throw error
        }
    }
    
    /// Force a full re-sync: delete *all* local recipes/courses/categories/tags and re-download
    /// everything from the server. One-way (server -> local); performs no uploads and no server
    /// deletions, so it's a safe recovery path (e.g. after local corruption or stale test data).
    public func forceFullResyncFromServer() async throws {
        progress = SyncProgress()

        do {
            progress.currentStep = "Authenticating..."
            try await ensureAuthenticated()
            _ = try await registerDevice() // ensure the device is registered (state is otherwise ignored)

            // Fetch the full server state first (so a failed download leaves local data intact).
            progress.currentStep = "Downloading from server..."
            let serverCourses = try await fetchListFromServer(ServerCourse.self, endpoint: "/api/courses")
            let serverCategories = try await fetchListFromServer(ServerCategory.self, endpoint: "/api/categories")
            let serverTags = try await fetchListFromServer(ServerTag.self, endpoint: "/api/tags")
            let serverShoppingLists = try await fetchListFromServer(ServerShoppingList.self, endpoint: "/api/shoppingLists")
            let serverRecipes = try await fetchRecipeDeltaPaged(modifiedSince: nil) // nil → all recipes

            // Anything the server sent that would trip the local filesystem or primary keys is refused
            // before the wipe, so a hostile or corrupt server can't leave an empty library behind.
            for serverRecipe in serverRecipes where !LibraryFilenames.isSafeComponent(serverRecipe.id) {
                throw SyncError.downloadFailed("Server sent a recipe with an invalid id")
            }

            // Shopping-list rows land with their sync bookkeeping (revision + snapshot) so the next
            // regular sync starts revision-based instead of legacy-seeding every row.
            let shoppingListRows = try serverShoppingLists.map { try syncedLocalRow(for: $0) }

            // The server's lists can carry a duplicated id (see the same guard in the ordinary sync
            // paths); collapse them here so the strict inserts below can't fail on a UNIQUE clash.
            let courseRows = Self.deduplicated(serverCourses.map {
                Course(id: $0.id, name: $0.name ?? "", lastModifiedDate: $0.lastModifiedDate ?? Date())
            }, by: \.id)
            let categoryRows = Self.deduplicated(serverCategories.map {
                Category(id: $0.id, name: $0.name ?? "", lastModifiedDate: $0.lastModifiedDate ?? Date())
            }, by: \.id)
            let tagRows = Self.deduplicated(serverTags.map {
                Tag(id: $0.id, name: $0.name ?? "", lastModifiedDate: $0.lastModifiedDate ?? Date())
            }, by: \.id)
            let listRows = Self.deduplicated(shoppingListRows, by: \.id)
            let recipeRows = Self.deduplicated(serverRecipes, by: \.id)

            let oldShoppingListIds = try await database.read { db in
                try ShoppingList.fetchAll(db).map { $0.id }
            }

            // Wipe and repopulate in ONE transaction. Anything that fails from here to the commit --
            // a decode error, a foreign-key clash, the app being killed -- rolls the wipe back too, so
            // the worst outcome is the library the user already had, never an empty one. Image files
            // are deleted only after the commit, for the same reason.
            progress.currentStep = "Replacing local data..."
            let oldImageFilenames = try await database.write { db -> [String] in
                let previousImages = try Recipe.fetchAll(db).compactMap { $0.imageFilename }

                try RecipeCategory.delete().execute(db)
                try RecipeTag.delete().execute(db)
                try Recipe.delete().execute(db)
                try Course.delete().execute(db)
                try Category.delete().execute(db)
                try Tag.delete().execute(db)
                try ShoppingList.delete().execute(db)

                // Courses/categories/tags first -- a downloaded recipe only links to ones that exist.
                for row in courseRows { try Course.insert { row }.execute(db) }
                for row in categoryRows { try Category.insert { row }.execute(db) }
                for row in tagRows { try Tag.insert { row }.execute(db) }
                for row in listRows { try ShoppingList.insert { row }.execute(db) }

                for serverRecipe in recipeRows {
                    try self.writeDownloadedRecipe(serverRecipe, in: db)
                }

                // Every recipe here came from the server moments ago, so the two sides agree by
                // construction. Recording that stops the next ordinary sync from reading the whole
                // restored library as never-agreed and uploading all of it straight back (SHARED-V0005).
                try RecipeAgreementStore.markAllAgreed(in: db)
                try ClassifierAgreementStore.markAllAgreed(in: db)

                // Deletions made here before the wipe are void: the server's copy is what the user
                // chose to keep. Left in place, the next ordinary sync would push them and delete
                // rows that were restored moments ago.
                try RecipeTombstoneWriter.clearAll(in: db)
                try ClassifierTombstoneWriter.clearAll(in: db)

                return previousImages
            }

            // Committed. The old image files are unreferenced now, and the image pass below refetches
            // every photo the server has.
            for filename in oldImageFilenames {
                images.deleteImage(filename: filename)
            }

            // Every list was replaced (or removed) wholesale; any open editor must reload rather
            // than save its pre-wipe content back.
            for id in Set(oldShoppingListIds).union(listRows.map { $0.id }) {
                await shoppingListChanged(id)
            }
            progress.itemsDownloaded += courseRows.count + categoryRows.count + tagRows.count + listRows.count
            progress.itemsDownloaded += recipeRows.count
            progress.downloadedRecipeIds.formUnion(recipeRows.map { $0.id })

            // Images: local files were wiped, so this only downloads (nothing to upload).
            progress.currentStep = "Downloading images..."
            try await syncImages()

            // The server's own classifiers can contain same-named rows; don't rebuild the local
            // library with them. The merge tombstones each loser, so the next ordinary sync deletes
            // it on the server too.
            progress.currentStep = "Tidying categories, courses, and tags..."
            await consolidateDuplicateLibraryItems()

            try await completeSyncOnServer()
            progress.currentStep = "Full re-sync complete!"
            logger.info("Force full re-sync complete: \(serverRecipes.count) recipes")
        } catch {
            logger.error("Force full re-sync failed at '\(self.progress.currentStep)': \(error)")
            throw error
        }
    }

    /// Force a full re-sync in the opposite direction: make the server an exact mirror of this
    /// device. Every local recipe/course/category/tag is pushed (overwriting the server copy), and
    /// anything present on the server but absent locally is deleted from the server. One-way
    /// (local -> server); the local database is the source of truth and its contents are never
    /// modified (only the shopping lists' sync-bookkeeping columns are refreshed as the server
    /// accepts each row), so it's a safe recovery path when the server holds stale or corrupt data.
    /// A failure partway leaves the server partially updated, but local data is untouched and a
    /// retry resolves it.
    public func forceFullResyncToServer() async throws {
        progress = SyncProgress()

        do {
            progress.currentStep = "Authenticating..."
            try await ensureAuthenticated()
            _ = try await registerDevice() // ensure the device is registered (state is otherwise ignored)

            // Snapshot the current server inventory so we know which items to overwrite vs. delete.
            progress.currentStep = "Inspecting server..."
            let serverCourses = try await fetchListFromServer(ServerCourse.self, endpoint: "/api/courses")
            let serverCategories = try await fetchListFromServer(ServerCategory.self, endpoint: "/api/categories")
            let serverTags = try await fetchListFromServer(ServerTag.self, endpoint: "/api/tags")
            let serverShoppingLists = try await fetchListFromServer(ServerShoppingList.self, endpoint: "/api/shoppingLists")
            let serverRecipeIds = try await fetchManifest().map { $0.id }

            // Read the full local state -- the source of truth, never modified here.
            let localCourses = try await database.read { db in try Course.fetchAll(db) }
            let localCategories = try await database.read { db in try Category.fetchAll(db) }
            let localTags = try await database.read { db in try Tag.fetchAll(db) }
            let localShoppingLists = try await database.read { db in try ShoppingList.fetchAll(db) }
            let localRecipes = try await database.read { db in try Recipe.fetchAll(db) }
            // Deletions recorded so far are carried out by the mirroring below (the rows are absent
            // here, so their server copies go), and cleared once it succeeds. Only these: one recorded
            // while this runs is for a row that was just pushed, and must still reach the server.
            let (recipeTombstones, classifierTombstones) = try await database.read { db in
                (try RecipeTombstoneWriter.pending(in: db),
                 try LibraryClassifier.allCases.map { ($0, try ClassifierTombstoneWriter.pending($0, in: db)) })
            }

            let serverCourseIds = Set(serverCourses.map { $0.id })
            let serverCategoryIds = Set(serverCategories.map { $0.id })
            let serverTagIds = Set(serverTags.map { $0.id })
            let serverShoppingListsById = Dictionary(serverShoppingLists.map { ($0.id, $0) }, uniquingKeysWith: { $1 })

            // Push courses/categories/tags first. Recipes link them by id, which must already exist
            // server-side. Update items the server already has, create the rest. `force` marks these
            // as deliberate mirror-this-device overwrites (see `forceWriteHeader`).
            progress.currentStep = "Uploading to server..."
            for c in localCourses {
                if serverCourseIds.contains(c.id) {
                    try await putToServer(c, endpoint: "/api/courses/\(c.id)", force: true)
                } else {
                    try await postToServer(c, endpoint: "/api/courses", force: true)
                }
            }
            for c in localCategories {
                if serverCategoryIds.contains(c.id) {
                    try await putToServer(c, endpoint: "/api/categories/\(c.id)", force: true)
                } else {
                    try await postToServer(c, endpoint: "/api/categories", force: true)
                }
            }
            for t in localTags {
                if serverTagIds.contains(t.id) {
                    try await putToServer(t, endpoint: "/api/tags/\(t.id)", force: true)
                } else {
                    try await postToServer(t, endpoint: "/api/tags", force: true)
                }
            }
            for l in localShoppingLists {
                var payload = ServerShoppingList(list: l)
                // Local is the source of truth here: base each save on the server's CURRENT revision
                // (0 = no server row) so the conditional save always accepts — the legacy
                // no-baseRevision path would let a newer server timestamp veto the push. A 409 means
                // a writer raced our inventory fetch; retry once against the row it returned, still
                // forcing this device's content. Each accepted save's revision + snapshot are
                // recorded so the next regular sync starts revision-based, contents untouched.
                payload.baseRevision = serverShoppingListsById[l.id]?.revision ?? 0
                var outcome = try await saveShoppingListOnServer(payload)
                if case .conflict(let current) = outcome {
                    payload.baseRevision = current.revision ?? 0
                    outcome = try await saveShoppingListOnServer(payload)
                }
                if case .saved(let accepted) = outcome {
                    try await markShoppingListSynced(accepted)
                }
            }
            progress.itemsUploaded += localCourses.count + localCategories.count + localTags.count + localShoppingLists.count

            // Push recipes (uploadRecipe overwrites existing or creates new as needed).
            progress.currentStep = "Uploading recipes..."
            for recipe in localRecipes {
                try await uploadRecipe(recipe, force: true)
                progress.itemsUploaded += 1
                progress.uploadedRecipeIds.insert(recipe.id)
            }

            // Remove anything on the server that no longer exists locally (it was deleted from the
            // source of truth). Recipes first, then classifiers they may reference.
            progress.currentStep = "Removing stale server data..."
            let localRecipeIds = Set(localRecipes.map { $0.id })
            let orphanRecipeIds = serverRecipeIds.filter { !localRecipeIds.contains($0) }
            if !orphanRecipeIds.isEmpty {
                try await deleteRecipesOnServer(recipeIds: orphanRecipeIds)
            }
            let localCourseIds = Set(localCourses.map { $0.id })
            for c in serverCourses where !localCourseIds.contains(c.id) {
                try await deleteOnServer(endpoint: "/api/courses/\(c.id)")
            }
            let localCategoryIds = Set(localCategories.map { $0.id })
            for c in serverCategories where !localCategoryIds.contains(c.id) {
                try await deleteOnServer(endpoint: "/api/categories/\(c.id)")
            }
            let localTagIds = Set(localTags.map { $0.id })
            for t in serverTags where !localTagIds.contains(t.id) {
                try await deleteOnServer(endpoint: "/api/tags/\(t.id)")
            }
            let localShoppingListIds = Set(localShoppingLists.map { $0.id })
            for l in serverShoppingLists where !localShoppingListIds.contains(l.id) {
                try await deleteOnServer(endpoint: "/api/shoppingLists/\(l.id)")
            }

            // Images: reconciled by timestamp. Because every recipe was just pushed with this device's
            // image metadata, the server never wins here; local images upload to fill any gaps.
            progress.currentStep = "Uploading images..."
            try await syncImages()

            // The server now mirrors this library exactly, so every local row is agreed by
            // construction. Recording that (SHARED-V0005) stops the next ordinary sync from
            // re-uploading every never-agreed row — and from resurrecting a recipe deleted elsewhere
            // between this push and that sync.
            try await database.write { db in
                try RecipeAgreementStore.markAllAgreed(in: db)
                try ClassifierAgreementStore.markAllAgreed(in: db)
                try RecipeTombstoneWriter.clear(recipeTombstones, in: db)
                for (kind, ids) in classifierTombstones {
                    try ClassifierTombstoneWriter.clear(kind, ids, in: db)
                }
            }

            try await completeSyncOnServer()
            progress.currentStep = "Full re-sync complete!"
            logger.info("Force full re-sync to server complete: \(localRecipes.count) recipes")
        } catch {
            logger.error("Force full re-sync to server failed at '\(self.progress.currentStep)': \(error)")
            throw error
        }
    }

    /// Guards bulk local deletions against a truncated/empty server response. The deletion
    /// heuristic ("present locally, absent from server, unchanged since last sync = deleted on
    /// the server") is dangerous if the server ever returns an empty list due to a transient
    /// failure rather than real deletions -- it would wipe local data. So if the server returned
    /// nothing while items are queued for local deletion, skip them (a later good sync resolves it).
    /// NOTE: this only catches a fully-empty response; detecting a *partial* response would require
    /// the server to also report its expected total count.
    private func serverResponseAllowsLocalDeletions(serverItemCount: Int, pendingLocalDeletions: Int, entity: String) -> Bool {
        if !RecipeSyncReconciler.allowsDeletions(sideCount: serverItemCount, pendingDeletions: pendingLocalDeletions) {
            logger.error("Skipping \(pendingLocalDeletions) local \(entity) deletion(s): the server returned an empty list, which likely indicates an incomplete response rather than real deletions.")
            return false
        }
        return true
    }

    /// The mirror of `serverResponseAllowsLocalDeletions`: guards bulk deletions **on the server**
    /// against an empty local collection.
    ///
    /// Deletion inference is symmetric — "present there, absent here, unchanged since the last sync"
    /// deletes on the server — so without this an empty library with a live watermark would ask the
    /// server to drop everything it has. A library is empty for the same kinds of reason a
    /// server list is: restored from a backup that predates the recipes, recreated at the old path
    /// after being moved, or opened before iCloud/Nextcloud finished bringing it down. This direction
    /// loses the shared copy rather than one device's.
    ///
    /// Only shopping lists still infer server deletions, so only they use it. Recipe and classifier
    /// deletions travel as tombstones, which this must not block. See SYNC-016.
    private func localLibraryAllowsServerDeletions(localItemCount: Int, pendingServerDeletions: Int, entity: String) -> Bool {
        if !RecipeSyncReconciler.allowsDeletions(sideCount: localItemCount, pendingDeletions: pendingServerDeletions) {
            logger.error("Skipping \(pendingServerDeletions) server \(entity) deletion(s): this library is empty, which likely indicates a restored or not-yet-downloaded library rather than real deletions. Use \"Delete Server, Push from Local\" if you meant to clear it.")
            return false
        }
        return true
    }

    // MARK: - Shopping List Sync (revision-based)

    /// A local shopping-list row plus its sync state, as the sync algorithm consumes it. Mirrors
    /// SaltyKMP's `LocalStore.LocalShoppingList`. `syncedSnapshot` is nil for legacy/never-synced
    /// rows — and for a snapshot that fails to decode (older build wrote junk?), which degrades to
    /// the same one-off timestamp-seeding path: never a crash, never data loss.
    private struct LocalShoppingListState {
        let list: ServerShoppingList
        let syncedRevision: Int64?
        let syncedSnapshot: ServerShoppingList?

        /// Edited since the last server agreement? Compares this device's own stamps only — no
        /// cross-machine clock comparison. Nil snapshot (legacy row) is the caller's case to handle.
        /// Compared at the wire's millisecond resolution: the row's Date (GRDB) and the snapshot's
        /// (wire JSON) can land on adjacent Doubles for the SAME millisecond.
        var isDirty: Bool {
            guard let syncedSnapshot else { return false }
            return list.lastModifiedDate?.roundedToWireMillis != syncedSnapshot.lastModifiedDate?.roundedToWireMillis
        }
    }

    /// Saving a shopping list is optimistic-concurrency-aware: a 409 is a first-class outcome
    /// carrying the CURRENT server row (the merge input), never an error.
    private enum ShoppingListSaveOutcome {
        case saved(ServerShoppingList)
        case conflict(current: ServerShoppingList)
    }

    private enum ShoppingListDeleteOutcome {
        case deleted
        case conflict(current: ServerShoppingList)
    }

    /// Shopping lists sync on per-row REVISIONS, not timestamps — a mirror of SaltyKMP's
    /// `SyncService.syncShoppingLists` (see salty_kmp/SHOPPING_LIST_REVISIONS_PLAN.md); keep the two
    /// in lockstep. For every row on both sides, two clock-free questions classify it:
    ///   dirty         — does the local row differ from its `syncedSnapshot` (last server agreement)?
    ///   serverChanged — does the server's `revision` differ from our `syncedRevision`?
    /// neither → in sync; dirty → upload (with baseRevision, so a race 409s instead of clobbering);
    /// serverChanged → download; BOTH → real conflict, resolved by `ShoppingListMerge` (three-way
    /// against the snapshot; freeform conflicts keep the local text as a new "conflicted copy" list).
    ///
    /// Legacy rows (no snapshot yet — pre-revision builds wrote them) get ONE timestamp-based
    /// decision to pick a direction, then the bookkeeping is seeded and every later sync is
    /// revision-based. Rows on only one side keep the watermark absence logic (no tombstones for
    /// lists, a deliberate FEATURE_PLANS.md decision), except server-side deletes now carry If-Match
    /// so a list that changed under us is downloaded instead of deleted.
    private func syncShoppingListsWithDeletions(deviceInfo: DeviceInfo) async throws {
        let serverLists = try await fetchListFromServer(ServerShoppingList.self, endpoint: "/api/shoppingLists")
        let localRows = try await database.read { db in
            try ShoppingList.fetchAll(db)
        }

        // uniquingKeysWith (not uniqueKeysWithValues) so a duplicate id from the server can't trap.
        let serverById = Dictionary(serverLists.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localIds = Set(localRows.map { $0.id })
        var toDeleteLocally: [String] = []

        for row in localRows {
            try Task.checkCancellation()
            let l = shoppingListState(of: row)
            guard let s = serverById[l.list.id] else {
                if let id = try await shoppingListAbsentOnServer(l, deviceInfo: deviceInfo) {
                    toDeleteLocally.append(id)
                }
                continue
            }
            if l.syncedRevision == nil || l.syncedSnapshot == nil {
                try await shoppingListLegacySeed(l, server: s)
                continue
            }
            let dirty = l.isDirty
            let serverChanged = s.revision != l.syncedRevision
            switch (dirty, serverChanged) {
            case (false, false):
                break
            case (true, false):
                try await uploadShoppingList(l.list, baseRevision: l.syncedRevision, snapshot: l.syncedSnapshot)
            case (false, true):
                try await downloadShoppingList(s)
            case (true, true):
                try await resolveShoppingListConflict(l, server: s)
            }
        }

        // Guarded against an empty/incomplete server response being read as "everything was deleted".
        if serverResponseAllowsLocalDeletions(serverItemCount: serverLists.count, pendingLocalDeletions: toDeleteLocally.count, entity: "shopping list") {
            try await database.write { [toDeleteLocally] db in
                for id in toDeleteLocally {
                    try ShoppingList.where { $0.id.eq(id) }.delete().execute(db)
                }
            }
            for id in toDeleteLocally {
                // An open editor for a deleted list should show it empty, not keep a ghost copy
                // whose edits would silently persist nowhere.
                await shoppingListChanged(id)
            }
            if !toDeleteLocally.isEmpty {
                logger.info("Deleted \(toDeleteLocally.count) shopping list(s) locally (were deleted on server)")
            }
        }

        // Server-only rows are classified before any of them is applied, because the delete direction
        // needs its total up front to be guarded the way the local direction above is (SYNC-016).
        //
        // Server-only row: new to us, or deleted here. No tombstones for lists, so the watermark
        // decides — except a failed If-Match delete proves the row changed, and change wins.
        var serverOnlyDownloads: [ServerShoppingList] = []
        var serverOnlyDeletes: [ServerShoppingList] = []
        for s in serverLists where !localIds.contains(s.id) {
            let serverDate = (s.lastModifiedDate ?? .distantPast).roundedToWireMillis
            if deviceInfo.isFirstSync || deviceInfo.lastSyncDate == nil || serverDate > deviceInfo.lastSyncDate! {
                serverOnlyDownloads.append(s)
            } else {
                serverOnlyDeletes.append(s)
            }
        }

        if !localLibraryAllowsServerDeletions(
            localItemCount: localRows.count, pendingServerDeletions: serverOnlyDeletes.count, entity: "shopping list") {
            serverOnlyDeletes = []
        }

        for s in serverOnlyDownloads {
            try Task.checkCancellation()
            try await downloadShoppingList(s)
        }

        for s in serverOnlyDeletes {
            try Task.checkCancellation()
            switch try await deleteShoppingListOnServer(id: s.id, expectedRevision: s.revision) {
            case .deleted:
                logger.info("Deleted shopping list \(s.id) on server (was deleted locally)")
            case .conflict(let current):
                try await downloadShoppingList(current)
            }
        }
    }

    /// Local row the server doesn't have: never-uploaded (push it) or server-deleted (respect it —
    /// unless we edited since). Returns the id to delete locally — deferred so the caller can apply
    /// the empty-response guard first — or nil when the row was uploaded instead.
    private func shoppingListAbsentOnServer(_ l: LocalShoppingListState, deviceInfo: DeviceInfo) async throws -> String? {
        // baseRevision 0 = "I expect NO server row": an insert sails through (the server accepts any
        // save of a row it doesn't have), but if another writer re-created the id between our GET and
        // this POST, the mismatch 409s into a proper merge instead of silently last-writer-winning.
        if l.syncedRevision != nil {
            if l.isDirty {
                // Deleted on the server but edited here since our last agreement: edit beats delete.
                try await uploadShoppingList(l.list, baseRevision: 0, snapshot: nil)
                return nil
            }
            return l.list.id
        }
        // Legacy/never-synced row: the old watermark logic, then the upload seeds the bookkeeping.
        let localDate = (l.list.lastModifiedDate ?? .distantPast).roundedToWireMillis
        if deviceInfo.isFirstSync || deviceInfo.lastSyncDate == nil || localDate > deviceInfo.lastSyncDate! {
            try await uploadShoppingList(l.list, baseRevision: 0, snapshot: nil)
            return nil
        }
        return l.list.id
    }

    /// Row exists on both sides but predates revision bookkeeping locally: ONE timestamp-based
    /// last-writer-wins decision (exactly what every sync did before revisions), whose outcome seeds
    /// `syncedRevision`/`syncedSnapshot` so this row never takes this path again.
    private func shoppingListLegacySeed(_ l: LocalShoppingListState, server s: ServerShoppingList) async throws {
        let localDate = (l.list.lastModifiedDate ?? .distantPast).roundedToWireMillis
        let serverDate = (s.lastModifiedDate ?? .distantPast).roundedToWireMillis
        if localDate > serverDate {
            try await uploadShoppingList(l.list, baseRevision: s.revision, snapshot: nil)
        } else if serverDate > localDate {
            try await downloadShoppingList(s)
        } else {
            try await markShoppingListSynced(s) // equal → agree; just record it
        }
    }

    /// Upload one list; a 409 means it changed since we fetched → resolve as a conflict instead.
    private func uploadShoppingList(_ list: ServerShoppingList, baseRevision: Int64?, snapshot: ServerShoppingList?) async throws {
        var payload = list
        payload.revision = nil
        payload.baseRevision = baseRevision
        switch try await saveShoppingListOnServer(payload) {
        case .saved(let accepted):
            try await markShoppingListSynced(accepted)
            progress.itemsUploaded += 1
        case .conflict(let current):
            try await resolveShoppingListConflict(
                LocalShoppingListState(list: list, syncedRevision: baseRevision, syncedSnapshot: snapshot),
                server: current
            )
        }
    }

    /// Both sides changed since the last agreement. Merge (three-way when a snapshot exists), push
    /// the result with the server's CURRENT revision as base, and store what the server accepted. A
    /// 409 on that push means yet another writer landed in between — retry once against the newest
    /// row; a second 409 leaves the row dirty for the next sync (never a wrong overwrite, by
    /// construction).
    private func resolveShoppingListConflict(
        _ l: LocalShoppingListState,
        server s: ServerShoppingList,
        retriesLeft: Int = 1
    ) async throws {
        let resolution = ShoppingListMerge.resolve(
            base: l.syncedSnapshot,
            local: l.list,
            server: s,
            conflictCopyId: UUIDV7().uuidString,
            conflictCopyLabel: "conflicted copy from \(deviceName) \(Self.dayStamp())"
        )

        // The conflict copy is a brand-new list: keep it locally and push it up like any other row.
        if let copy = resolution.conflictCopy {
            let copyRow = copy.asShoppingList // no agreement to record yet (nil bookkeeping)
            try await database.write { db in
                try ShoppingList.upsert { copyRow }.execute(db)
            }
            switch try await saveShoppingListOnServer(copy) {
            case .saved(let accepted):
                try await markShoppingListSynced(accepted)
                progress.itemsUploaded += 1
            case .conflict:
                break // fresh id — can't happen; next sync retries
            }
            logger.info("Kept a conflicted copy of shopping list \(l.list.id) as \(copy.id)")
        }

        var merged = resolution.merged
        merged.baseRevision = s.revision
        switch try await saveShoppingListOnServer(merged) {
        case .saved(let accepted):
            try await downloadShoppingList(accepted) // contents + bookkeeping land together, row is clean
            progress.itemsUploaded += 1
        case .conflict(let current):
            if retriesLeft > 0 {
                try await resolveShoppingListConflict(
                    LocalShoppingListState(list: resolution.merged, syncedRevision: l.syncedRevision, syncedSnapshot: l.syncedSnapshot),
                    server: current,
                    retriesLeft: retriesLeft - 1
                )
            }
            // else: give up this round; the row stays dirty and next sync re-merges
        }
    }

    /// Writes a server-agreed row: contents and sync bookkeeping move together, so the row lands
    /// already-clean with server row itself as the snapshot.
    private func downloadShoppingList(_ server: ServerShoppingList) async throws {
        let row = try syncedLocalRow(for: server)
        try await database.write { db in
            try ShoppingList.upsert { row }.execute(db)
        }
        progress.itemsDownloaded += 1
        // The list may be open in a checklist/freeform editor, which holds its content in memory —
        // without this, its next keystroke would save the pre-download content right back.
        await shoppingListChanged(server.id)
    }

    /// Records the server agreement after a successful *upload* without touching the row's contents:
    /// [accepted] is the server's response (our content plus the revision it assigned).
    private func markShoppingListSynced(_ accepted: ServerShoppingList) async throws {
        let revision = accepted.revision
        let snapshot = try shoppingListSnapshotJson(accepted)
        try await database.write { db in
            try db.execute(
                sql: #"UPDATE "shoppingList" SET "syncedRevision" = ?, "syncedSnapshot" = ? WHERE "id" = ?"#,
                arguments: [revision, snapshot, accepted.id]
            )
        }
    }

    /// The local row for a server-agreed payload: contents plus the bookkeeping columns.
    private func syncedLocalRow(for server: ServerShoppingList) throws -> ShoppingList {
        var row = server.asShoppingList
        row.syncedRevision = server.revision
        row.syncedSnapshot = try shoppingListSnapshotJson(server)
        return row
    }

    /// Wire-JSON snapshot of a server-agreed row (the future merge base), encoded with the wire
    /// encoder so one serialization covers both storage and transfer. Nil when the server didn't
    /// return a revision (pre-v3.2 server without this data); such a row stays on the legacy-seeding path.
    private func shoppingListSnapshotJson(_ list: ServerShoppingList) throws -> String? {
        guard list.revision != nil else { return nil }
        var snapshot = list
        snapshot.baseRevision = nil
        return String(data: try makeWireEncoder().encode(snapshot), encoding: .utf8)
    }

    /// The sync algorithm's view of one local row: its wire form plus the decoded snapshot.
    private func shoppingListState(of row: ShoppingList) -> LocalShoppingListState {
        LocalShoppingListState(
            list: ServerShoppingList(list: row),
            syncedRevision: row.syncedRevision,
            syncedSnapshot: row.syncedSnapshot.flatMap { json in
                try? makeWireDecoder().decode(ServerShoppingList.self, from: Data(json.utf8))
            }
        )
    }

    /// POSTs one shopping list and decodes the outcome: 2xx → the saved row (now carrying the
    /// server-assigned revision); 409 → the CURRENT server row, for the caller to merge against.
    private func saveShoppingListOnServer(_ list: ServerShoppingList) async throws -> ShoppingListSaveOutcome {
        let url = try makeURL(endpoint: "/api/shoppingLists")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        request.httpBody = try makeWireEncoder().encode(list)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.uploadFailed("No HTTP response saving shopping list \(list.id)")
        }
        if httpResponse.statusCode == 409 {
            return .conflict(current: try makeWireDecoder().decode(ServerShoppingList.self, from: data))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            logger.error("Shopping list save failed HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
            throw SyncError.uploadFailed(SyncError.httpMessage(status: httpResponse.statusCode, body: data))
        }
        return .saved(try makeWireDecoder().decode(ServerShoppingList.self, from: data))
    }

    /// DELETEs one shopping list, conditional on [expectedRevision] via If-Match when present. A 409
    /// means the list changed past that revision — edit beats delete; the current row rides in the
    /// body so the caller downloads it instead. 404 counts as deleted: the goal state is already true.
    private func deleteShoppingListOnServer(id: String, expectedRevision: Int64?) async throws -> ShoppingListDeleteOutcome {
        let url = try makeURL(endpoint: "/api/shoppingLists/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)
        if let expectedRevision {
            request.setValue(String(expectedRevision), forHTTPHeaderField: "If-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.uploadFailed("No HTTP response deleting shopping list \(id)")
        }
        if httpResponse.statusCode == 409 {
            return .conflict(current: try makeWireDecoder().decode(ServerShoppingList.self, from: data))
        }
        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            throw SyncError.uploadFailed("DELETE shopping list \(id) failed: \(SyncError.httpMessage(status: httpResponse.statusCode, body: data))")
        }
        return .deleted
    }

    /// Today as "yyyy-MM-dd" (UTC), for conflict-copy labels; mirrors SaltyKMP's `nowDayStamp()`.
    private static func dayStamp(_ date: Date = Date()) -> String {
        String(SyncWireDate.string(from: date).prefix(10))
    }

    // MARK: - Conditional classifier deletes

    /// Outcome of a conditional course/category/tag delete: a 409 means the row changed on the
    /// server after we fetched it, and carries the CURRENT row for the caller to download instead.
    private enum LibraryDeleteOutcome<Item: Decodable> {
        case deleted
        case conflict(current: Item)
    }

    /// DELETEs one course/category/tag, conditional on [expectedLastModified] via `If-Match`
    /// carrying the wire timestamp string. Today's server ignores the header and deletes
    /// unconditionally, so behavior is unchanged; a future server (planned alongside web editing)
    /// compares it against the stored stamp and answers 409 + the current row on mismatch — the
    /// same edit-beats-delete contract shopping lists already have via If-Match revisions. Sent
    /// only by the regular sync path: the force re-sync-to-server deletes stay unconditional,
    /// because there the local library is deliberately the source of truth.
    /// 404 counts as deleted: the goal state is already true.
    private func deleteLibraryItemOnServer<Item: Decodable>(
        _ type: Item.Type, endpoint: String, expectedLastModified: Date?
    ) async throws -> LibraryDeleteOutcome<Item> {
        let url = try makeURL(endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)
        if let expectedLastModified {
            request.setValue(Self.wireDateString(expectedLastModified), forHTTPHeaderField: "If-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.uploadFailed("No HTTP response for DELETE \(endpoint)")
        }
        if httpResponse.statusCode == 409 {
            return .conflict(current: try makeWireDecoder().decode(Item.self, from: data))
        }
        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            throw SyncError.uploadFailed("DELETE to \(endpoint) failed: \(SyncError.httpMessage(status: httpResponse.statusCode, body: data))")
        }
        return .deleted
    }

    /// True when the server's copy of a row changed after this device's last sync: the "edit beats a
    /// delete" test a tombstone must pass before it's pushed. Never true on a first sync, when there is
    /// no watermark to measure an edit against (the same rule recipe tombstones follow).
    private static func serverCopyChangedSinceLastSync(_ serverModified: Date?, deviceInfo: DeviceInfo) -> Bool {
        guard !deviceInfo.isFirstSync, let watermark = deviceInfo.lastSyncDate, let serverModified else {
            return false
        }
        return serverModified.roundedToWireMillis > watermark
    }

    // MARK: - Course Sync

    private func syncCoursesWithDeletions(deviceInfo: DeviceInfo) async throws {
        let serverCourses = try await fetchListFromServer(ServerCourse.self, endpoint: "/api/courses")
        // Agreement-tracked (SHARED-V0006), exactly like recipes: a row that exists here and not on
        // the server is classified by its recorded stamp, never by comparing clocks to the watermark.
        let (localCourses, tracksAgreement, syncedStamps, tombstones) = try await database.read {
            db -> ([Course], Bool, [String: Date], Set<String>) in
            (try Course.fetchAll(db),
             try ClassifierAgreementStore.isAvailable(.course, in: db),
             try ClassifierAgreementStore.stamps(.course, in: db),
             try ClassifierTombstoneWriter.pending(.course, in: db))
        }
        
        // uniquingKeysWith (not uniqueKeysWithValues) so a duplicate id in the server response
        // can't trap/crash the sync; keep the last occurrence.
        let serverCoursesById = Dictionary(serverCourses.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localCourseIds = Set(localCourses.map { $0.id })

        var toDeleteOnServer: [ServerCourse] = []
        var toDeleteLocally: [String] = []
        
        // Process each local course
        for localCourse in localCourses {
            if let serverCourse = serverCoursesById[localCourse.id] {
                // Exists on both - compare timestamps for updates
                let serverDate = (serverCourse.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                let localDate = (localCourse.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                
                if localDate > serverDate {
                    try await putToServer(localCourse, endpoint: "/api/courses/\(localCourse.id)")
                    progress.itemsUploaded += 1
                } else if serverDate > localDate {
                    let course = Course(id: serverCourse.id, name: serverCourse.name ?? "", lastModifiedDate: serverDate)
                    try await database.write { db in
                        try Course.upsert { course }.execute(db)
                    }
                    progress.itemsDownloaded += 1
                }
            } else {
                // Only exists locally
                if deviceInfo.isFirstSync {
                    try await postToServer(localCourse, endpoint: "/api/courses")
                    progress.itemsUploaded += 1
                } else if tracksAgreement {
                    // Recorded fact, not a clock comparison. No stamp means it has never been to the
                    // server, so it is new here; a stamp that no longer matches means it was edited here
                    // after the server last had it, and an edit beats a delete everywhere in Salty. Only
                    // a stamp that still matches proves the server had exactly this row and removed it.
                    let localDate = (localCourse.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if let stamp = syncedStamps[localCourse.id], stamp.roundedToWireMillis == localDate {
                        toDeleteLocally.append(localCourse.id)
                    } else {
                        try await postToServer(localCourse, endpoint: "/api/courses")
                        progress.itemsUploaded += 1
                    }
                } else if let lastSync = deviceInfo.lastSyncDate {
                    // Pre-V0006 library: the old watermark guess, until this file is migrated.
                    let localDate = (localCourse.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if localDate > lastSync {
                        try await postToServer(localCourse, endpoint: "/api/courses")
                        progress.itemsUploaded += 1
                    } else {
                        toDeleteLocally.append(localCourse.id)
                    }
                } else {
                    try await postToServer(localCourse, endpoint: "/api/courses")
                    progress.itemsUploaded += 1
                }
            }
        }
        
        // Process courses only on server. An absence alone proves nothing (a restored backup, another
        // device's upload), so the row is downloaded unless a tombstone records it was deleted here --
        // and even then an edit beats a delete: a server copy changed since this device's last sync
        // comes back. Tombstones for rows that are back here, or already gone there, are settled.
        var settledTombstones = tombstones.filter { localCourseIds.contains($0) || serverCoursesById[$0] == nil }
        for serverCourse in serverCoursesById.values where !localCourseIds.contains(serverCourse.id) {
            let tombstoned = tombstones.contains(serverCourse.id)
            if tombstoned && !Self.serverCopyChangedSinceLastSync(serverCourse.lastModifiedDate, deviceInfo: deviceInfo) {
                toDeleteOnServer.append(serverCourse)
                continue
            }
            let course = Course(
                id: serverCourse.id,
                name: serverCourse.name ?? "",
                lastModifiedDate: serverCourse.lastModifiedDate?.roundedToWireMillis ?? Date()
            )
            try await database.write { db in
                try Course.insert { course }.execute(db)
            }
            progress.itemsDownloaded += 1
            if tombstoned {
                settledTombstones.insert(serverCourse.id)
                logger.info("Course \(serverCourse.id) changed on the server after it was deleted here; downloaded instead of deleting")
            }
        }

        // Delete locally (guarded against empty-response wipes; batched in one transaction)
        let coursesToDeleteLocally = toDeleteLocally
        if serverResponseAllowsLocalDeletions(serverItemCount: serverCourses.count, pendingLocalDeletions: coursesToDeleteLocally.count, entity: "course") {
            try await database.write { db in
                for id in coursesToDeleteLocally {
                    try Course.where { $0.id.eq(id) }.delete().execute(db)
                }
            }
            if !coursesToDeleteLocally.isEmpty {
                logger.info("Deleted \(coursesToDeleteLocally.count) course(s) locally (were deleted on server)")
            }
        }
        
        // Delete on server: tombstoned rows only, so no empty-library guard -- deleting every course is
        // legitimate. Conditional on the timestamp the decision was based on, so a row that changed
        // after our fetch (e.g. a web rename racing this sync) is downloaded, not deleted.
        for serverCourse in toDeleteOnServer {
            switch try await deleteLibraryItemOnServer(
                ServerCourse.self,
                endpoint: "/api/courses/\(serverCourse.id)",
                expectedLastModified: serverCourse.lastModifiedDate
            ) {
            case .deleted:
                logger.info("Deleted course \(serverCourse.id) on server (was deleted locally)")
            case .conflict(let current):
                let course = Course(id: current.id, name: current.name ?? "", lastModifiedDate: current.lastModifiedDate ?? Date())
                try await database.write { db in
                    try Course.upsert { course }.execute(db)
                }
                progress.itemsDownloaded += 1
                logger.info("Course \(current.id) changed on server after our fetch; downloaded instead of deleting")
            }
            settledTombstones.insert(serverCourse.id)
        }
        if !settledTombstones.isEmpty {
            let settled = settledTombstones
            try await database.write { db in
                try ClassifierTombstoneWriter.clear(.course, settled, in: db)
            }
        }
        // Record what this pass agreed on (SHARED-V0006): everything the server also holds, plus what
        // this pass moved in either direction, minus anything just deleted here — the same three groups
        // the recipe pass stamps, for the same reason.
        if tracksAgreement {
            var agreed = Set(localCourses.map { $0.id }).intersection(serverCoursesById.keys)
            agreed.formUnion(serverCoursesById.keys.filter { !localCourseIds.contains($0) })
            agreed.subtract(toDeleteLocally)
            let stampIds = Array(agreed)
            try await database.write { db in
                try ClassifierAgreementStore.markAgreed(.course, stampIds, in: db)
            }
        }

    }
    
    // MARK: - Duplicate library items

    /// Folds same-named courses/categories/tags into a single row at the end of a sync.
    ///
    /// Classifier rows are reconciled by **id**, never by name (see `syncCoursesWithDeletions` and
    /// its siblings), so two devices that each create "Vegan" -- or two installs that each ran the
    /// migration-0002 seed and got their own ids for "Breads", "Main", … -- end up with two rows
    /// that sync then replicates faithfully, forever. Nothing upstream can notice: to the server
    /// they are simply two different rows that happen to share a name.
    ///
    /// The merge itself re-points every recipe before deleting the duplicate, so no recipe loses a
    /// classification, and the survivor is chosen by **id** rather than by recipe count: counts
    /// differ from device to device, and only an id-based rule makes every device pick the same
    /// winner. Once they agree, the loser's deletion propagates on the following sync (the merge
    /// tombstones it) and the library converges.
    ///
    /// Deliberately runs *after* the downloads: a recipe arriving in this same sync still sees both
    /// ids and keeps its membership, and the merge then re-points it and bumps its
    /// `lastModifiedDate` so the correction uploads. The remaining gap is a recipe created on
    /// another device that references the loser id and arrives *after* this device deleted it --
    /// `downloadRecipe` skips ids it doesn't know, so that one membership is dropped locally. That
    /// window is one sync cycle wide (the other device runs the same pass and re-points its own
    /// recipes), and it never touches a recipe this device already has.
    ///
    /// Best-effort: a failure here must not fail an otherwise-good sync.
    private func consolidateDuplicateLibraryItems() async {
        do {
            let summary = try await database.write { db in
                try LibraryDuplicateMerger.consolidateDuplicates(in: db)
            }
            if !summary.isEmpty {
                logger.info("""
                    Consolidated \(summary.removedItems) duplicate library item(s) across \
                    \(summary.mergedGroups) name(s); \(summary.touchedRecipes) recipe(s) re-pointed
                    """)
            }
        } catch {
            // Logged, not thrown: the sync itself succeeded, and the manual Consolidate Duplicates
            // command remains available.
            logger.error("Post-sync duplicate consolidation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Category Sync

    private func syncCategoriesWithDeletions(deviceInfo: DeviceInfo) async throws {
        let serverCategories = try await fetchListFromServer(ServerCategory.self, endpoint: "/api/categories")
        // Agreement-tracked (SHARED-V0006), exactly like recipes: a row that exists here and not on
        // the server is classified by its recorded stamp, never by comparing clocks to the watermark.
        let (localCategories, tracksAgreement, syncedStamps, tombstones) = try await database.read {
            db -> ([Category], Bool, [String: Date], Set<String>) in
            (try Category.fetchAll(db),
             try ClassifierAgreementStore.isAvailable(.category, in: db),
             try ClassifierAgreementStore.stamps(.category, in: db),
             try ClassifierTombstoneWriter.pending(.category, in: db))
        }
        
        let serverCategoriesById = Dictionary(serverCategories.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localCategoryIds = Set(localCategories.map { $0.id })

        var toDeleteOnServer: [ServerCategory] = []
        var toDeleteLocally: [String] = []
        
        // Process each local category
        for localCategory in localCategories {
            if let serverCategory = serverCategoriesById[localCategory.id] {
                // Exists on both - compare timestamps for updates
                let serverDate = (serverCategory.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                let localDate = (localCategory.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                
                if localDate > serverDate {
                    try await putToServer(localCategory, endpoint: "/api/categories/\(localCategory.id)")
                    progress.itemsUploaded += 1
                } else if serverDate > localDate {
                    let category = Category(id: serverCategory.id, name: serverCategory.name ?? "", lastModifiedDate: serverDate)
                    try await database.write { db in
                        try Category.upsert { category }.execute(db)
                    }
                    progress.itemsDownloaded += 1
                }
            } else {
                // Only exists locally
                if deviceInfo.isFirstSync {
                    try await postToServer(localCategory, endpoint: "/api/categories")
                    progress.itemsUploaded += 1
                } else if tracksAgreement {
                    // Recorded fact, not a clock comparison. No stamp means it has never been to the
                    // server, so it is new here; a stamp that no longer matches means it was edited here
                    // after the server last had it, and an edit beats a delete everywhere in Salty. Only
                    // a stamp that still matches proves the server had exactly this row and removed it.
                    let localDate = (localCategory.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if let stamp = syncedStamps[localCategory.id], stamp.roundedToWireMillis == localDate {
                        toDeleteLocally.append(localCategory.id)
                    } else {
                        try await postToServer(localCategory, endpoint: "/api/categories")
                        progress.itemsUploaded += 1
                    }
                } else if let lastSync = deviceInfo.lastSyncDate {
                    // Pre-V0006 library: the old watermark guess, until this file is migrated.
                    let localDate = (localCategory.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if localDate > lastSync {
                        try await postToServer(localCategory, endpoint: "/api/categories")
                        progress.itemsUploaded += 1
                    } else {
                        toDeleteLocally.append(localCategory.id)
                    }
                } else {
                    try await postToServer(localCategory, endpoint: "/api/categories")
                    progress.itemsUploaded += 1
                }
            }
        }
        
        // Process categories only on server (tombstone rules as for courses)
        var settledTombstones = tombstones.filter { localCategoryIds.contains($0) || serverCategoriesById[$0] == nil }
        for serverCategory in serverCategoriesById.values where !localCategoryIds.contains(serverCategory.id) {
            let tombstoned = tombstones.contains(serverCategory.id)
            if tombstoned && !Self.serverCopyChangedSinceLastSync(serverCategory.lastModifiedDate, deviceInfo: deviceInfo) {
                toDeleteOnServer.append(serverCategory)
                continue
            }
            let category = Category(
                id: serverCategory.id,
                name: serverCategory.name ?? "",
                lastModifiedDate: serverCategory.lastModifiedDate?.roundedToWireMillis ?? Date()
            )
            try await database.write { db in
                try Category.insert { category }.execute(db)
            }
            progress.itemsDownloaded += 1
            if tombstoned {
                settledTombstones.insert(serverCategory.id)
                logger.info("Category \(serverCategory.id) changed on the server after it was deleted here; downloaded instead of deleting")
            }
        }

        // Delete locally (guarded against empty-response wipes; batched in one transaction)
        let categoriesToDeleteLocally = toDeleteLocally
        if serverResponseAllowsLocalDeletions(serverItemCount: serverCategories.count, pendingLocalDeletions: categoriesToDeleteLocally.count, entity: "category") {
            try await database.write { db in
                for id in categoriesToDeleteLocally {
                    try Category.where { $0.id.eq(id) }.delete().execute(db)
                }
            }
            if !categoriesToDeleteLocally.isEmpty {
                logger.info("Deleted \(categoriesToDeleteLocally.count) category(ies) locally (were deleted on server)")
            }
        }
        
        // Delete on server: tombstoned rows only, conditional on the fetched timestamp (as for courses)
        for serverCategory in toDeleteOnServer {
            switch try await deleteLibraryItemOnServer(
                ServerCategory.self,
                endpoint: "/api/categories/\(serverCategory.id)",
                expectedLastModified: serverCategory.lastModifiedDate
            ) {
            case .deleted:
                logger.info("Deleted category \(serverCategory.id) on server (was deleted locally)")
            case .conflict(let current):
                let category = Category(id: current.id, name: current.name ?? "", lastModifiedDate: current.lastModifiedDate ?? Date())
                try await database.write { db in
                    try Category.upsert { category }.execute(db)
                }
                progress.itemsDownloaded += 1
                logger.info("Category \(current.id) changed on server after our fetch; downloaded instead of deleting")
            }
            settledTombstones.insert(serverCategory.id)
        }
        if !settledTombstones.isEmpty {
            let settled = settledTombstones
            try await database.write { db in
                try ClassifierTombstoneWriter.clear(.category, settled, in: db)
            }
        }
        // Record what this pass agreed on (SHARED-V0006): everything the server also holds, plus what
        // this pass moved in either direction, minus anything just deleted here — the same three groups
        // the recipe pass stamps, for the same reason.
        if tracksAgreement {
            var agreed = Set(localCategories.map { $0.id }).intersection(serverCategoriesById.keys)
            agreed.formUnion(serverCategoriesById.keys.filter { !localCategoryIds.contains($0) })
            agreed.subtract(toDeleteLocally)
            let stampIds = Array(agreed)
            try await database.write { db in
                try ClassifierAgreementStore.markAgreed(.category, stampIds, in: db)
            }
        }

    }
    
    // MARK: - Tag Sync
    
    private func syncTagsWithDeletions(deviceInfo: DeviceInfo) async throws {
        let serverTags = try await fetchListFromServer(ServerTag.self, endpoint: "/api/tags")
        // Agreement-tracked (SHARED-V0006), exactly like recipes: a row that exists here and not on
        // the server is classified by its recorded stamp, never by comparing clocks to the watermark.
        let (localTags, tracksAgreement, syncedStamps, tombstones) = try await database.read {
            db -> ([Tag], Bool, [String: Date], Set<String>) in
            (try Tag.fetchAll(db),
             try ClassifierAgreementStore.isAvailable(.tag, in: db),
             try ClassifierAgreementStore.stamps(.tag, in: db),
             try ClassifierTombstoneWriter.pending(.tag, in: db))
        }
        
        let serverTagsById = Dictionary(serverTags.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localTagIds = Set(localTags.map { $0.id })

        var toDeleteOnServer: [ServerTag] = []
        var toDeleteLocally: [String] = []
        
        // Process each local tag
        for localTag in localTags {
            if let serverTag = serverTagsById[localTag.id] {
                // Exists on both - compare timestamps for updates
                let serverDate = (serverTag.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                let localDate = (localTag.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                
                if localDate > serverDate {
                    try await putToServer(localTag, endpoint: "/api/tags/\(localTag.id)")
                    progress.itemsUploaded += 1
                } else if serverDate > localDate {
                    let tag = Tag(id: serverTag.id, name: serverTag.name ?? "", lastModifiedDate: serverDate)
                    try await database.write { db in
                        try Tag.upsert { tag }.execute(db)
                    }
                    progress.itemsDownloaded += 1
                }
            } else {
                // Only exists locally
                if deviceInfo.isFirstSync {
                    try await postToServer(localTag, endpoint: "/api/tags")
                    progress.itemsUploaded += 1
                } else if tracksAgreement {
                    // Recorded fact, not a clock comparison. No stamp means it has never been to the
                    // server, so it is new here; a stamp that no longer matches means it was edited here
                    // after the server last had it, and an edit beats a delete everywhere in Salty. Only
                    // a stamp that still matches proves the server had exactly this row and removed it.
                    let localDate = (localTag.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if let stamp = syncedStamps[localTag.id], stamp.roundedToWireMillis == localDate {
                        toDeleteLocally.append(localTag.id)
                    } else {
                        try await postToServer(localTag, endpoint: "/api/tags")
                        progress.itemsUploaded += 1
                    }
                } else if let lastSync = deviceInfo.lastSyncDate {
                    // Pre-V0006 library: the old watermark guess, until this file is migrated.
                    let localDate = (localTag.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if localDate > lastSync {
                        try await postToServer(localTag, endpoint: "/api/tags")
                        progress.itemsUploaded += 1
                    } else {
                        toDeleteLocally.append(localTag.id)
                    }
                } else {
                    try await postToServer(localTag, endpoint: "/api/tags")
                    progress.itemsUploaded += 1
                }
            }
        }
        
        // Process tags only on server (tombstone rules as for courses)
        var settledTombstones = tombstones.filter { localTagIds.contains($0) || serverTagsById[$0] == nil }
        for serverTag in serverTagsById.values where !localTagIds.contains(serverTag.id) {
            let tombstoned = tombstones.contains(serverTag.id)
            if tombstoned && !Self.serverCopyChangedSinceLastSync(serverTag.lastModifiedDate, deviceInfo: deviceInfo) {
                toDeleteOnServer.append(serverTag)
                continue
            }
            let tag = Tag(
                id: serverTag.id,
                name: serverTag.name ?? "",
                lastModifiedDate: serverTag.lastModifiedDate?.roundedToWireMillis ?? Date()
            )
            try await database.write { db in
                try Tag.insert { tag }.execute(db)
            }
            progress.itemsDownloaded += 1
            if tombstoned {
                settledTombstones.insert(serverTag.id)
                logger.info("Tag \(serverTag.id) changed on the server after it was deleted here; downloaded instead of deleting")
            }
        }

        // Delete locally (guarded against empty-response wipes; batched in one transaction)
        let tagsToDeleteLocally = toDeleteLocally
        if serverResponseAllowsLocalDeletions(serverItemCount: serverTags.count, pendingLocalDeletions: tagsToDeleteLocally.count, entity: "tag") {
            try await database.write { db in
                for id in tagsToDeleteLocally {
                    try Tag.where { $0.id.eq(id) }.delete().execute(db)
                }
            }
            if !tagsToDeleteLocally.isEmpty {
                logger.info("Deleted \(tagsToDeleteLocally.count) tag(s) locally (were deleted on server)")
            }
        }
        
        // Delete on server: tombstoned rows only, conditional on the fetched timestamp (as for courses)
        for serverTag in toDeleteOnServer {
            switch try await deleteLibraryItemOnServer(
                ServerTag.self,
                endpoint: "/api/tags/\(serverTag.id)",
                expectedLastModified: serverTag.lastModifiedDate
            ) {
            case .deleted:
                logger.info("Deleted tag \(serverTag.id) on server (was deleted locally)")
            case .conflict(let current):
                let tag = Tag(id: current.id, name: current.name ?? "", lastModifiedDate: current.lastModifiedDate ?? Date())
                try await database.write { db in
                    try Tag.upsert { tag }.execute(db)
                }
                progress.itemsDownloaded += 1
                logger.info("Tag \(current.id) changed on server after our fetch; downloaded instead of deleting")
            }
            settledTombstones.insert(serverTag.id)
        }
        if !settledTombstones.isEmpty {
            let settled = settledTombstones
            try await database.write { db in
                try ClassifierTombstoneWriter.clear(.tag, settled, in: db)
            }
        }
        // Record what this pass agreed on (SHARED-V0006): everything the server also holds, plus what
        // this pass moved in either direction, minus anything just deleted here — the same three groups
        // the recipe pass stamps, for the same reason.
        if tracksAgreement {
            var agreed = Set(localTags.map { $0.id }).intersection(serverTagsById.keys)
            agreed.formUnion(serverTagsById.keys.filter { !localTagIds.contains($0) })
            agreed.subtract(toDeleteLocally)
            let stampIds = Array(agreed)
            try await database.write { db in
                try ClassifierAgreementStore.markAgreed(.tag, stampIds, in: db)
            }
        }

    }
    
    // MARK: - Device-based Recipe Sync with Deletion Detection
    
    /// Device info returned from server
    struct DeviceInfo {
        let deviceId: String
        let lastSyncDate: Date?
        let isFirstSync: Bool
    }
    
    /// Register this device with the server
    private func registerDevice() async throws -> DeviceInfo {
        guard let url = URL(string: "\(serverUrl)/api/recipes/sync/device") else {
            throw SyncError.uploadFailed("Invalid server URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        let body: [String: String] = [
            "deviceId": deviceId,
            "deviceName": deviceName
        ]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SyncError.uploadFailed("Failed to register device")
        }
        
        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let isFirstSync = json["isFirstSync"] as? Bool ?? true
        
        // Parse lastSyncDate if present
        var lastSyncDate: Date?
        if let dateStr = json["lastSyncDate"] as? String {
            lastSyncDate = parseServerDate(dateStr)
            logger.debug("Parsed lastSyncDate: \(dateStr) -> \(lastSyncDate?.description ?? "nil")")
        }
        
        logger.info("Device info from server: isFirstSync=\(isFirstSync), lastSyncDate=\(lastSyncDate?.description ?? "nil")")

        // A device with no lastSyncDate has never FINISHED a sync, whatever the flag says — and since
        // device sync tokens landed, the flag says otherwise. Enrolment issues the token into the same
        // device_sync row that carries the watermark, so the row already exists by the time this call
        // is made, and the server's "is this device new?" test is only whether the row is there.
        //
        // Normalised HERE, at the one place the server's answer is parsed, rather than at each of the
        // half-dozen places that branch on it — the branches that upload are harmless either way, and
        // the ones that delete are not, so the two must not be able to drift apart.
        //
        // Not cosmetic. isFirstSync is what suppresses deletion inference (SYNC-006), and a stamp
        // records agreement with "the server" — a device that has never synced with THIS one has no
        // basis to assume the stamps in a shared library refer to it. Trusting them deletes every
        // stamped, unmodified row the server does not have. SYNC-008's tie-breaker settles the
        // direction: losing a recipe is worse than resurrecting one.
        return DeviceInfo(
            deviceId: deviceId,
            lastSyncDate: lastSyncDate,
            isFirstSync: isFirstSync || lastSyncDate == nil
        )
    }
    
    /// Mark sync as complete on server. Public so its non-2xx throw is unit-testable.
    public func completeSyncOnServer() async throws {
        guard let url = URL(string: "\(serverUrl)/api/recipes/sync/device/\(deviceId)/complete") else {
            throw SyncError.uploadFailed("Invalid server URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)
        
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SyncError.uploadFailed("Failed to mark sync complete on server: \(SyncError.httpMessage(status: statusCode, body: data))")
        }
    }
    
    /// Sync recipes with deletion detection based on device's last sync time
    private func syncRecipesWithDeletions(deviceInfo: DeviceInfo) async throws {
        // 1. Full manifest (every server recipe's id + lastModifiedDate). This is the COMPLETE set the
        //    deletion logic reconciles against — never the delta below.
        let fullManifest = try await fetchManifest()

        // 1a. Deletions made here, pushed as recorded facts rather than inferred from absence as in earlier
        //     versions. Without this, a second device/app sharing the same file can tell only "never downloaded", but
        //     if the recipe was edited on a third device since that  watermark, this will incorrectly revive that recipe.
        //
        //     An edit still beats a delete, and manifest is fetched first so the tombstones
        //     can be checked against it before anything is pushed.
        var tombstones = Set(try await database.read { db in try RecipeTombstoneWriter.pending(in: db) })
        if !tombstones.isEmpty {
            let manifestById = Dictionary(fullManifest.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            let editedSinceDeleted = tombstones.filter { id in
                guard !deviceInfo.isFirstSync, let watermark = deviceInfo.lastSyncDate,
                      let entry = manifestById[id], let serverDate = entry.lastModifiedDate else { return false }
                return serverDate.roundedToWireMillis > watermark
            }

            if !editedSinceDeleted.isEmpty {
                logger.info("Dropping \(editedSinceDeleted.count) tombstone(s): the server copy changed after the delete")
                let toClear = Array(editedSinceDeleted)
                try await database.write { db in try RecipeTombstoneWriter.clear(toClear, in: db) }
                tombstones.subtract(editedSinceDeleted)
            }

            if !tombstones.isEmpty {
                logger.info("Pushing \(tombstones.count) recorded deletion(s) to the server")
                try await deleteRecipesOnServer(recipeIds: Array(tombstones))
                let pushed = Array(tombstones)
                try await database.write { db in try RecipeTombstoneWriter.clear(pushed, in: db) }
            }
        }

        // Anything just deleted on the server must not then be reconciled as if it were still there.
        let manifest = fullManifest.filter { !tombstones.contains($0.id) }

        // 2. Only the changed bodies (the modifiedSince delta), paged. First sync / no lastSync date
        //    → fetch everything (still paged).
        let cutoff = (deviceInfo.isFirstSync || deviceInfo.lastSyncDate == nil) ? nil : deviceInfo.lastSyncDate
        let deltaRecipes = try await fetchRecipeDeltaPaged(modifiedSince: cutoff)
        let deltaById = Dictionary(deltaRecipes.map { ($0.id, $0) }, uniquingKeysWith: { $1 })

        // 3. Local snapshot.
        let localRecipes = try await database.read { db in
            try Recipe.fetchAll(db)
        }
        let localRecipesById = Dictionary(localRecipes.map { ($0.id, $0) }, uniquingKeysWith: { $1 })

        // 4. Reconcile (pure, unit-tested in RecipeSyncReconcilerTests). Missing server timestamps map
        //    to distantPast, matching the previous `?? Date.distantPast` behavior.
        // Compare at the wire's resolution (whole milliseconds). The local Date (decoded by SQLiteData
        // from "yyyy-MM-dd HH:mm:ss.SSS") and the server Date (decoded by ISO8601DateFormatter from
        // "...SSS'Z'") can land on adjacent Doubles for the SAME millisecond, so a strict > / < made the
        // reconciler re-upload/re-download every recipe on every sync. roundedToWireMillis normalizes both.
        // SHARED-V0005's agreement bookkeeping. See RecipeAgreementStore for why the column is not a
        // property on `Recipe`.
        let (tracksAgreement, syncedStamps) = try await database.read { db -> (Bool, [String: Date]) in
            (try RecipeAgreementStore.isAvailable(in: db), try RecipeAgreementStore.stamps(in: db))
        }

        let localEntries = localRecipes.map {
            RecipeSyncReconciler.Entry(
                id: $0.id,
                lastModified: $0.lastModifiedDate.roundedToWireMillis,
                // Rounded like lastModified, and it is load-bearing: the reconciler compares the two
                // for equality, and rounding only one side makes an UNCHANGED row read as edited.
                syncedModified: syncedStamps[$0.id]?.roundedToWireMillis
            )
        }
        let serverEntries = manifest.map {
            RecipeSyncReconciler.Entry(id: $0.id, lastModified: ($0.lastModifiedDate ?? Date.distantPast).roundedToWireMillis)
        }
        let plan = RecipeSyncReconciler.plan(
            local: localEntries,
            server: serverEntries,
            isFirstSync: deviceInfo.isFirstSync,
            lastSyncDate: deviceInfo.lastSyncDate,
            tracksAgreement: tracksAgreement
        )

        logger.info("Sync plan: \(plan.toUpload.count) upload, \(plan.toDownload.count) download, \(plan.toDeleteLocally.count) delete-local, \(plan.toDeleteOnServer.count) delete-server (manifest \(manifest.count), delta \(deltaRecipes.count))")

        // 5. Uploads. Each is a single request, so a cancel between them just leaves the rest for next time.
        for recipeId in plan.toUpload {
            try Task.checkCancellation()
            guard let localRecipe = localRecipesById[recipeId] else { continue }
            try await uploadRecipe(localRecipe)
            progress.itemsUploaded += 1
            progress.uploadedRecipeIds.insert(recipeId)
        }

        /*
         * 6. Downloads — the plan's, PLUS everything it wanted deleted from the SERVER.
         *
         * The plan's rule for a row the server has and we do not is a clock comparison: older than our
         * watermark means "we had it and deleted it". That is the reasoning SHARED-V0005 replaced on the
         * local side with a recorded fact, and it is no better here. A deliberate deletion does not reach
         * this branch at all — it travels as a TOMBSTONE, pushed and cleared above, and filtered out of
         * the manifest — so what lands here is a row we cannot prove we deleted.
         *
         * What produces one is the library losing its memory rather than a clock disagreeing. Point the
         * app at a different bundle (FileHelper keeps a security-scoped bookmark for exactly that) and
         * the device id, which is per install, brings the previous library's watermark with it: every
         * recipe the new library lacks reads as one this device deleted. Restoring an older library over
         * a current watermark does the same. Neither is caught by the empty-library guard, because the
         * library is not empty — it is simply a different one.
         *
         * So the row is taken rather than destroyed. The cost is a deletion whose tombstone was lost
         * coming back, to be deleted again; the cost of the alternative is recipes nobody deleted going
         * from every device at once. SYNC-008 already states the preference — "losing a recipe is worse
         * than resurrecting one" — and SYNC-007 applies it in the local direction. This is the same rule
         * in the direction that was missing it. Downloading rather than merely skipping also CONVERGES:
         * the row exists here afterwards, so the next sync sees an ordinary two-sided row.
         *
         * Deliberately NOT a change to RecipeSyncReconciler.plan, which is the cross-client contract
         * SaltyKMP implements too and the corpus pins. SaltyKMP declines the same list at the same point.
         *
         * Use the delta body when present, otherwise fetch that single recipe (covers the rare case
         * where the server copy is newer than local but predates lastSync).
         */
        let toDownload = plan.toDownload + plan.toDeleteOnServer
        for recipeId in toDownload {
            try Task.checkCancellation()
            let serverRecipe: ServerRecipe
            if let body = deltaById[recipeId] {
                serverRecipe = body
            } else {
                serverRecipe = try await fetchRecipeById(recipeId)
            }
            try await downloadRecipe(serverRecipe)
            progress.itemsDownloaded += 1
            progress.downloadedRecipeIds.insert(recipeId)
        }

        // 7. Deletions — local deletes are guarded against empty-response wipes using the COMPLETE
        //    manifest count, and batched in one transaction.
        // Judged against the FULL manifest: filtering our own tombstones out of it must not make the
        // server look emptier than it is and trip the mass-deletion guard.
        if serverResponseAllowsLocalDeletions(serverItemCount: fullManifest.count, pendingLocalDeletions: plan.toDeleteLocally.count, entity: "recipe") {
            for recipeId in plan.toDeleteLocally {
                logger.info("Deleting recipe \(recipeId) locally (was deleted on another device)")
            }
            try await database.write { db in
                for recipeId in plan.toDeleteLocally {
                    _ = try Recipe.deleteOne(db, key: recipeId)
                }
            }
            // Rows are gone; only now are their files unreferenced.
            for recipeId in plan.toDeleteLocally {
                if let recipe = localRecipesById[recipeId], let filename = recipe.imageFilename {
                    images.deleteImage(filename: filename)
                }
            }
            progress.itemsDownloaded += plan.toDeleteLocally.count // Count as sync actions
        }

        // Nothing is deleted on the server here. A deliberate deletion is a tombstone, pushed above; the
        // plan's guess is downloaded instead. See the note on `toDownload`.
        if !plan.toDeleteLocally.isEmpty || !plan.toDeleteOnServer.isEmpty {
            logger.info("Deletion sync: \(plan.toDeleteLocally.count) deleted locally, \(plan.toDeleteOnServer.count) taken from the server rather than deleted")
        }

        // 8. Record what this pass agreed on, so the next one needn't guess (SHARED-V0005). Three groups
        //    mean the same thing afterwards — the server's copy matches this row as it stands: what went
        //    up, what came down, and what was already identical on both sides. Anything just deleted
        //    locally is excluded, and so is anything the delete guard held back, since those are still
        //    local-only and carry whatever stamp they already had.
        if tracksAgreement {
            let manifestIds = Set(manifest.map { $0.id })
            var agreed = Set(localRecipes.map { $0.id }).intersection(manifestIds)
            agreed.formUnion(plan.toUpload)
            agreed.formUnion(toDownload)
            agreed.subtract(plan.toDeleteLocally)

            // A `let` snapshot: the write closure runs off this actor and cannot capture a var.
            let agreedIds = Array(agreed)
            if !agreedIds.isEmpty {
                try await database.write { db in
                    try RecipeAgreementStore.markAgreed(agreedIds, in: db)
                }
            }
        }

        // 9. "Last made on" dates, which the body plan above is blind to by design.
        try await syncPreparedDates(manifest: manifest, plan: plan, downloaded: toDownload)
    }

    /// Independent "last made on" reconciliation, keyed on `lastModifiedPreparedDate` — the same decoupling
    /// as `syncImages`, for the opposite reason. Images get their own channel because re-sending bytes on a
    /// body edit is EXPENSIVE; prepared dates get one because marking a recipe made deliberately does NOT
    /// bump `lastModifiedDate` (that would shove the recipe to the top of the "Date Modified" sort every
    /// time you cook it), so the body reconciler never sees the change.
    ///
    /// Newer stamp wins; a nil stamp means "never marked made through a prepared-date-aware client" and
    /// always loses. A whole-row upload is what moves the value — safe because the bodies agree by the
    /// time a push happens here, so it re-sends matching content and moves only the prepared pair,
    /// needing no partial-update endpoint.
    ///
    /// Recipes whose bodies moved this cycle need only ONE direction, because the body transfer already
    /// carried the prepared pair through a merge at the far end (`RecipeRepository.upsert` server-side,
    /// `downloadRecipe` locally), both keyed on this same stamp:
    ///   - body UPLOADED — the server kept its own pair exactly when its stamp was newer, so only a pull
    ///     can still be owed. Pushing again would be a no-op.
    ///   - body DOWNLOADED — the local merge kept its own pair exactly when the local stamp was newer, so
    ///     only a push can still be owed.
    /// Skipping such ids entirely (the obvious simplification) leaves the losing side stale until the
    /// NEXT sync. Mirror of SaltyKMP's `SyncService.syncPreparedDates`.
    /// - Parameter downloaded: what was ACTUALLY downloaded, which is the plan's list plus the rows it
    ///   wanted deleted from the server (see the note at the call site). Passed in rather than read off
    ///   the plan so that a resurrected row counts as downloaded — it is a live row on both sides, and
    ///   calling it deleted here would be the one place this file still described it as gone.
    private func syncPreparedDates(
        manifest: [ServerRecipeManifestEntry],
        plan: RecipeSyncReconciler.Plan,
        downloaded: [String]
    ) async throws {
        let uploadedBodies = Set(plan.toUpload)
        let downloadedBodies = Set(downloaded)
        let deleted = Set(plan.toDeleteLocally)
        // Read AFTER the body plan ran, so downloaded rows show their post-merge prepared pair.
        let localRecipes = try await database.read { db in try Recipe.fetchAll(db) }
        let localById = Dictionary(localRecipes.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        var uploaded = 0
        var downloaded = 0

        for entry in manifest {
            try Task.checkCancellation()
            // Intersection only: a recipe missing on either side has no body agreement to piggyback on.
            guard !deleted.contains(entry.id), let local = localById[entry.id] else { continue }
            let serverStamp = (entry.lastModifiedPreparedDate ?? .distantPast).roundedToWireMillis
            let localStamp = (local.lastModifiedPreparedDate ?? .distantPast).roundedToWireMillis
            if localStamp > serverStamp, !uploadedBodies.contains(entry.id) {
                try await uploadRecipe(local)
                uploaded += 1
            } else if serverStamp > localStamp, !downloadedBodies.contains(entry.id) {
                // Targeted write, like the image path: deliberately does NOT touch lastModifiedDate.
                try await database.write { db in
                    try db.execute(sql: """
                        UPDATE recipe
                        SET lastPrepared = ?, lastModifiedPreparedDate = ?
                        WHERE id = ?
                        """,
                        arguments: [entry.lastPrepared, entry.lastModifiedPreparedDate, entry.id]
                    )
                }
                downloaded += 1
            }
        }

        if uploaded > 0 || downloaded > 0 {
            progress.itemsUploaded += uploaded
            progress.itemsDownloaded += downloaded
            logger.info("Prepared-date sync: \(uploaded) uploaded, \(downloaded) downloaded")
        }
    }

    /// Delete recipes on the server. Public so its non-2xx throw is unit-testable.
    public func deleteRecipesOnServer(recipeIds: [String]) async throws {
        guard let url = URL(string: "\(serverUrl)/api/recipes/sync/delete") else {
            throw SyncError.uploadFailed("Invalid server URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        let body: [String: Any] = [
            "deviceId": deviceId,
            "recipeIds": recipeIds
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SyncError.uploadFailed("Failed to delete recipes on server: \(SyncError.httpMessage(status: statusCode, body: data))")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let deleted = json["deleted"] as? Int {
            logger.info("Server deleted \(deleted) recipe(s)")
        }
    }
    
    /// Parse server date string to Date
    private func parseServerDate(_ dateStr: String) -> Date? {
        SyncWireDate.date(from: dateStr)
    }
    
    private func uploadRecipe(_ recipe: Recipe, force: Bool = false) async throws {
        // Convert to server format
        var serverRecipe = ServerRecipe.from(recipe)
        
        // Load category and tag IDs from junction tables
        let (categoryIds, tagIds) = try await database.read { db in
            let categories = try RecipeCategory
                .where { $0.recipeId.eq(recipe.id) }
                .fetchAll(db)
            let tags = try RecipeTag
                .where { $0.recipeId.eq(recipe.id) }
                .fetchAll(db)
            return (categories.map { $0.categoryId }, tags.map { $0.tagId })
        }
        serverRecipe.categoryIds = categoryIds
        serverRecipe.tagIds = tagIds
        
        // Check if recipe exists on server
        let exists = try await checkExists(endpoint: "/api/recipes/\(recipe.id)")
        
        if exists {
            try await putToServer(serverRecipe, endpoint: "/api/recipes/\(recipe.id)", force: force)
        } else {
            try await postToServer(serverRecipe, endpoint: "/api/recipes", force: force)
        }
        
        logger.info("Uploaded recipe: \(recipe.name) with \(categoryIds.count) categories (IDs: \(categoryIds)) and \(tagIds.count) tags (IDs: \(tagIds))")
    }
    
    /// Keeps the first row for each key, so a server list that repeats an id can't fail a strict insert.
    private static func deduplicated<Row, Key: Hashable>(_ rows: [Row], by key: KeyPath<Row, Key>) -> [Row] {
        var seen = Set<Key>()
        return rows.filter { seen.insert($0[keyPath: key]).inserted }
    }

    private func downloadRecipe(_ serverRecipe: ServerRecipe) async throws {
        // The id becomes the image file's name on disk, so it has to be a plain file name -- a server
        // could otherwise write outside the images folder through the image pass.
        guard LibraryFilenames.isSafeComponent(serverRecipe.id) else {
            throw SyncError.downloadFailed("Server sent a recipe with an invalid id")
        }

        logger.info("downloadRecipe called for '\(serverRecipe.name)' with categoryIds: \(serverRecipe.categoryIds ?? []), tagIds: \(serverRecipe.tagIds ?? [])")

        try await database.write { db in
            try self.writeDownloadedRecipe(serverRecipe, in: db)
        }
        logger.info("Downloaded recipe complete: \(serverRecipe.name)")
    }

    /// Upserts one server recipe and its category/tag links inside the caller's transaction.
    ///
    /// Nonisolated so it can run inside a `database.write` closure: the ordinary sync wraps one recipe
    /// per transaction, while a force pull writes the whole library in a single one.
    nonisolated private func writeDownloadedRecipe(_ serverRecipe: ServerRecipe, in db: Database) throws {
        let recipe = serverRecipe.toLocalRecipe()

        // The server has no FK on course_id, so it can serve a recipe whose course was deleted.
        // Writing that dangling courseId would fail the local `courseId → course` FK, so null it on a
        // local copy. (Courses sync before recipes, so a still-valid course is already present here.)
        var toWrite = recipe
        if let cid = toWrite.courseId,
           try Int.fetchOne(db, sql: #"SELECT 1 FROM "course" WHERE "id" = ?"#, arguments: [cid]) == nil {
            logger.warning("Recipe '\(toWrite.name)' references missing course \(cid); clearing it.")
            toWrite.courseId = nil
        }

        // Check if recipe already exists
        let existing = try Recipe.where { $0.id.eq(recipe.id) }.fetchOne(db)

        // Image state (filename, thumbnail, image timestamp) is owned ENTIRELY by the image-sync pass,
        // never the body. Preserve the local image for an existing recipe so a text-only body update
        // can't wipe it; leave a brand-new recipe imageless so the image pass sees the server image as
        // newer and downloads its bytes.
        toWrite.imageFilename = existing?.imageFilename
        toWrite.imageThumbnailData = existing?.imageThumbnailData
        toWrite.lastModifiedImageDate = existing?.lastModifiedImageDate

        // The "last made on" pair rides along with the body, but the body's clock doesn't decide it:
        // keep whichever side's lastModifiedPreparedDate is newer. Without this, downloading a body
        // edit made elsewhere would silently undo a mark-as-made this device hasn't uploaded yet.
        // (The server applies the same merge on upsert, so both directions agree.)
        if let existing,
           (existing.lastModifiedPreparedDate ?? .distantPast).roundedToWireMillis
             > (toWrite.lastModifiedPreparedDate ?? .distantPast).roundedToWireMillis {
            toWrite.lastPrepared = existing.lastPrepared
            toWrite.lastModifiedPreparedDate = existing.lastModifiedPreparedDate
        }

        if existing != nil {
            try Recipe.update(toWrite).execute(db)
            logger.debug("Updated existing recipe: \(recipe.name)")
        } else {
            try Recipe.insert { toWrite }.execute(db)
            logger.debug("Inserted new recipe: \(recipe.name)")
        }
        
        // Update category relationships
        // First delete existing relationships for this recipe
        try RecipeCategory
            .where { $0.recipeId.eq(recipe.id) }
            .delete()
            .execute(db)
        logger.debug("Deleted existing category relationships for recipe \(recipe.id)")
        
        // Insert new category relationships
        if let categoryIds = serverRecipe.categoryIds {
            logger.info("Inserting \(categoryIds.count) category relationships for \(recipe.name)")
            for categoryId in categoryIds {
                // Check if category exists locally
                let categoryExists = try Category.where { $0.id.eq(categoryId) }.fetchOne(db) != nil
                if !categoryExists {
                    logger.warning("Category \(categoryId) does not exist locally - skipping relationship")
                    continue
                }
                
                let rc = RecipeCategory(
                    id: SaltyId.new(),
                    recipeId: recipe.id,
                    categoryId: categoryId
                )
                if try RecipeCategory.insertIfAbsent(rc, in: db) {
                    logger.debug("Inserted RecipeCategory: recipe=\(recipe.id), category=\(categoryId)")
                }
            }
        }
        
        // Update tag relationships
        try RecipeTag
            .where { $0.recipeId.eq(recipe.id) }
            .delete()
            .execute(db)
        logger.debug("Deleted existing tag relationships for recipe \(recipe.id)")
        
        // Insert new tag relationships
        if let tagIds = serverRecipe.tagIds {
            logger.info("Inserting \(tagIds.count) tag relationships for \(recipe.name)")
            for tagId in tagIds {
                // Check if tag exists locally
                let tagExists = try Tag.where { $0.id.eq(tagId) }.fetchOne(db) != nil
                if !tagExists {
                    logger.warning("Tag \(tagId) does not exist locally - skipping relationship")
                    continue
                }
                
                let rt = RecipeTag(
                    id: SaltyId.new(),
                    recipeId: recipe.id,
                    tagId: tagId
                )
                if try RecipeTag.insertIfAbsent(rt, in: db) {
                    logger.debug("Inserted RecipeTag: recipe=\(recipe.id), tag=\(tagId)")
                }
            }
        }
    }
    
    // MARK: - Image Sync
    
    /// Independent image reconciliation, decoupled from the recipe-body sync and keyed on
    /// `lastModifiedImageDate`. For each recipe the newer image side wins: push the local image (or its
    /// removal) when local is newer, pull the server image (or apply its removal) when the server is newer.
    /// With EQUAL image dates (incl. the legacy null==null state) an image is still propagated to whichever
    /// side never received it, and a local image whose file went missing is recovered. Image BYTES move
    /// only when the image actually changed — a text-only edit never re-transfers them.
    private func syncImages() async throws {
        let manifest = try await fetchManifest()
        let serverById = Dictionary(manifest.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localRecipes = try await database.read { db in try Recipe.fetchAll(db) }
        let localById = Dictionary(localRecipes.map { ($0.id, $0) }, uniquingKeysWith: { $1 })

        var imageErrors: [String] = []
        logger.info("Image sync starting (\(manifest.count) server, \(localRecipes.count) local)")

        for id in Set(serverById.keys).union(localById.keys) {
            try Task.checkCancellation()
            let server = serverById[id]
            let local = localById[id]
            let serverDate = (server?.lastModifiedImageDate ?? .distantPast).roundedToWireMillis
            let localDate = (local?.lastModifiedImageDate ?? .distantPast).roundedToWireMillis
            let serverFile = server?.imageFilename
            let localFile = local?.imageFilename
            do {
                if localDate > serverDate {
                    // Local image change wins → push it (or its removal) to the server.
                    if let localFile, let data = images.loadImage(filename: localFile) {
                        try await uploadImage(data, for: id, imageDate: local?.lastModifiedImageDate)
                        progress.imagesUploaded += 1
                    } else if serverFile != nil {
                        try await deleteServerImage(for: id, imageDate: local?.lastModifiedImageDate)
                        progress.imagesUploaded += 1
                    }
                } else if serverDate > localDate {
                    // Server image change wins → pull it (or apply its removal) locally.
                    if let serverFile {
                        try await downloadImage(filename: serverFile, for: id, imageDate: server?.lastModifiedImageDate)
                        progress.imagesDownloaded += 1
                    } else if localFile != nil {
                        try await clearLocalImage(for: id, imageDate: server?.lastModifiedImageDate)
                        progress.imagesDownloaded += 1
                    }
                } else {
                    // Equal image dates: propagate an image the other side never received, or recover a local
                    // image whose file is missing. (A removal stamps a fresh, unequal date — equality is never
                    // a removal.)
                    if let serverFile, localFile == nil {
                        try await downloadImage(filename: serverFile, for: id, imageDate: server?.lastModifiedImageDate)
                        progress.imagesDownloaded += 1
                    } else if let localFile, serverFile == nil,
                              let data = images.loadImage(filename: localFile) {
                        try await uploadImage(data, for: id, imageDate: local?.lastModifiedImageDate)
                        progress.imagesUploaded += 1
                    } else if let serverFile, let localFile,
                              images.loadImage(filename: localFile) == nil {
                        try await downloadImage(filename: serverFile, for: id, imageDate: server?.lastModifiedImageDate)
                        progress.imagesDownloaded += 1
                    }
                }
            } catch {
                // A cancel must abort the whole loop; otherwise every remaining recipe "fails" instantly
                // and the tally below reports a bogus image-sync failure.
                if SyncError.isCancellation(error) { throw error }
                logger.error("Image sync failed for recipe \(id): \(error.localizedDescription)")
                imageErrors.append(id)
            }
        }

        logger.info("Image sync: \(self.progress.imagesUploaded) uploaded, \(self.progress.imagesDownloaded) downloaded, \(imageErrors.count) failed")
        if !imageErrors.isEmpty, progress.imagesUploaded == 0, progress.imagesDownloaded == 0 {
            throw SyncError.uploadFailed("Image sync failed for: \(imageErrors.joined(separator: ", "))")
        }
    }
    
    /// Uploads image bytes. [imageDate] (the recipe's lastModifiedImageDate) is sent as a form field and
    /// stored verbatim server-side so this device never sees the server image as "newer" and re-downloads it.
    private func uploadImage(_ imageData: Data, for recipeId: String, imageDate: Date?) async throws {
        // URL-encode the recipe ID
        guard let encodedRecipeId = recipeId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(serverUrl)/api/recipes/\(encodedRecipeId)/image") else {
            throw SyncError.uploadFailed("Invalid recipe ID for URL: \(recipeId)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Prepare image data with the platform's converter (the Apple app's turns HEIC into PNG and
        // WebP into JPEG; see `PreparedSyncImage.passThrough` for the default).
        let prepared = await prepareImage(imageData)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.\(prepared.fileExtension)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(prepared.mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(prepared.data)
        body.append("\r\n".data(using: .utf8)!)
        if let imageDate {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"lastModifiedImageDate\"\r\n\r\n".data(using: .utf8)!)
            body.append(Self.wireDateString(imageDate).data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.uploadFailed("No HTTP response received")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to get error details from response
            let errorBody = String(data: responseData, encoding: .utf8) ?? "No response body"
            logger.error("Image upload failed with status \(httpResponse.statusCode): \(errorBody)")
            throw SyncError.uploadFailed("Image upload failed (HTTP \(httpResponse.statusCode))")
        }
    }
    
    /// Percent-encodes a server-supplied image filename as a SINGLE path component: unlike
    /// `.urlPathAllowed`, "/" is also encoded, so a hostile value can't traverse out of
    /// `/api/recipes/images/` and steer the authenticated request to another endpoint. Legit
    /// filenames are always `<recipeId>.<ext>`, which this encoding leaves untouched.
    /// Public for unit testing.
    public static func encodedImagePathComponent(_ filename: String) -> String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return filename.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    /// Downloads image bytes and records the server's [imageDate] locally, so the next sync sees the local
    /// and server image timestamps as equal and doesn't re-transfer.
    /// [maxBytes] rejects an oversized (hostile or corrupt) response before it's written to disk/database;
    /// syncImages treats the throw as a per-recipe failure, so one bad image doesn't abort the whole sync.
    /// Public so its failure-path throws are unit-testable; maxBytes is injectable so the
    /// cap can be tested without a multi-hundred-MB fixture.
    public func downloadImage(filename: String, for recipeId: String, imageDate: Date?,
                       maxBytes: Int = ServerSyncEngine.maxImageDownloadBytes) async throws {
        // `filename` is server-controlled; percent-encode it and guard the URL so a malformed name
        // surfaces as a recoverable error instead of crashing the sync.
        guard let encodedFilename = Self.encodedImagePathComponent(filename),
              let url = URL(string: "\(serverUrl)/api/recipes/images/\(encodedFilename)") else {
            throw SyncError.downloadFailed("Invalid image URL for filename: \(filename)")
        }
        logger.debug("Downloading image from: \(url)")

        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        // Streamed under the cap rather than buffered then measured: a response with no
        // Content-Length would otherwise be held in full before the size check could run.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, maxBytes: maxBytes)
        } catch let tooLarge as ResponseTooLargeError {
            throw SyncError.downloadFailed("Image '\(filename)' is over the \(tooLarge.limit)-byte sync limit (\(tooLarge.observed) bytes); skipping")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.downloadFailed("No HTTP response for image download: \(filename)")
        }

        guard httpResponse.statusCode == 200 else {
            throw SyncError.downloadFailed("Image download failed for '\(filename)': \(SyncError.httpMessage(status: httpResponse.statusCode, body: data))")
        }

        logger.debug("Downloaded image '\(filename)': \(data.count) bytes")

        // Save image locally and update recipe (filename + thumbnail + image timestamp together).
        // Detached: saveImage writes the file AND renders the list thumbnail, and there's no reason to
        // hold this actor for the decode while other work waits on it.
        let images = self.images
        let saved = await Task.detached(priority: .userInitiated) {
            images.saveImage(data, for: recipeId)
        }.value
        if let result = saved {
            logger.debug("Saved image as '\(result.filename)' with \(result.thumbnailData.count) byte thumbnail")
            try await database.write { db in
                try db.execute(sql: """
                    UPDATE recipe
                    SET imageFilename = ?, imageThumbnailData = ?, lastModifiedImageDate = ?
                    WHERE id = ?
                    """,
                    arguments: [result.filename, result.thumbnailData, imageDate, recipeId]
                )
            }
            // Row committed; an older file under another extension is unreferenced now.
            images.deleteImages(for: recipeId, except: result.filename)
            logger.info("Updated recipe \(recipeId) with downloaded image")
        } else {
            throw SyncError.downloadFailed("Failed to save downloaded image for recipe \(recipeId)")
        }
    }

    /// Removes the recipe's image on the server, sending the (client-authoritative) removal timestamp.
    private func deleteServerImage(for recipeId: String, imageDate: Date?) async throws {
        guard let encodedId = recipeId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw SyncError.uploadFailed("Invalid recipe ID for URL: \(recipeId)")
        }
        var components = URLComponents(string: "\(serverUrl)/api/recipes/\(encodedId)/image")
        if let imageDate { components?.queryItems = [URLQueryItem(name: "lastModifiedImageDate", value: Self.wireDateString(imageDate))] }
        guard let url = components?.url else { throw SyncError.uploadFailed("Invalid URL for image delete: \(recipeId)") }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SyncError.uploadFailed("Image delete failed for recipe \(recipeId)")
        }
    }

    /// Clears the recipe's local image (file + filename + thumbnail) and records the server's removal
    /// timestamp, applying a server-side image deletion locally.
    private func clearLocalImage(for recipeId: String, imageDate: Date?) async throws {
        let filename = try await database.read { db in
            try Recipe.where { $0.id.eq(recipeId) }.fetchOne(db)?.imageFilename
        }
        try await database.write { db in
            try db.execute(sql: """
                UPDATE recipe
                SET imageFilename = NULL, imageThumbnailData = NULL, lastModifiedImageDate = ?
                WHERE id = ?
                """,
                arguments: [imageDate, recipeId]
            )
        }
        // Row no longer references the file; delete it only now.
        if let filename { images.deleteImage(filename: filename) }
    }

    /// The wire timestamp format the server expects (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`, milliseconds).
    private static func wireDateString(_ date: Date) -> String {
        SyncWireDate.string(from: date)
    }

    // MARK: - Network Helpers
    
    private func fetchFromServer<T: Decodable>(_ type: T.Type, endpoint: String) async throws -> T {
        try await fetchFromServerWithTotalCount(type, endpoint: endpoint).value
    }

    /// Page size for the paginated recipe delta.
    private static let syncPageSize = 100

    /// Fetches the lightweight recipe manifest (id + lastModifiedDate for ALL of the user's recipes).
    /// Uses the X-Total-Count completeness check, since this is the set deletion reconciliation relies on.
    private func fetchManifest() async throws -> [ServerRecipeManifestEntry] {
        try await fetchListFromServer(ServerRecipeManifestEntry.self, endpoint: "/api/recipes/sync/manifest")
    }

    /// Fetches a single recipe body by id (fallback when a to-download recipe isn't in the delta).
    private func fetchRecipeById(_ id: String) async throws -> ServerRecipe {
        try await fetchFromServer(ServerRecipe.self, endpoint: "/api/recipes/\(id)")
    }

    /// Fetches recipe bodies as the paginated `modifiedSince` delta. When `modifiedSince` is nil the
    /// whole table is paged through (e.g. first sync). All pages are accumulated and verified against
    /// the server's X-Total-Count, so a truncated fetch aborts rather than silently dropping recipes.
    private func fetchRecipeDeltaPaged(modifiedSince: Date?) async throws -> [ServerRecipe] {
        var sinceParam = ""
        if let modifiedSince {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let iso = formatter.string(from: modifiedSince)
            let encoded = iso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? iso
            sinceParam = "modifiedSince=\(encoded)&"
        }

        var all: [ServerRecipe] = []
        var page = 0
        var expectedTotal: Int?
        while true {
            let endpoint = "/api/recipes?\(sinceParam)page=\(page)&size=\(Self.syncPageSize)"
            let (items, totalCount) = try await fetchFromServerWithTotalCount([ServerRecipe].self, endpoint: endpoint)
            if expectedTotal == nil { expectedTotal = totalCount }
            all.append(contentsOf: items)
            if let total = expectedTotal, all.count >= total { break }
            if items.count < Self.syncPageSize { break }   // short page → no more results
            page += 1
        }

        if let total = expectedTotal, all.count != total {
            logger.error("Paged recipe delta incomplete: collected \(all.count) of \(total); aborting to avoid a partial sync.")
            throw SyncError.networkError("Incomplete paged recipe delta (\(all.count)/\(total))")
        }
        return all
    }

    /// Fetches a list and verifies it against the server's `X-Total-Count` header (when present),
    /// throwing if the response is incomplete. This stops the deletion logic from ever running on a
    /// partial list (which would treat missing items as deletions). Backward compatible: a server
    /// that omits the header skips the check.
    private func fetchListFromServer<Element: Decodable>(_ elementType: Element.Type, endpoint: String) async throws -> [Element] {
        let (items, totalCount) = try await fetchFromServerWithTotalCount([Element].self, endpoint: endpoint)
        if let totalCount, totalCount != items.count {
            logger.error("Incomplete response from \(endpoint): received \(items.count) of \(totalCount) expected items; aborting sync to avoid treating missing items as deletions.")
            throw SyncError.networkError("Incomplete response from \(endpoint) (\(items.count)/\(totalCount))")
        }
        return items
    }

    /// Builds a request URL from `serverUrl` and an endpoint path, throwing rather than force-unwrapping
    /// so a misconfigured server URL can't crash a sync.
    private func makeURL(endpoint: String) throws -> URL {
        guard let url = URL(string: "\(serverUrl)\(endpoint)") else {
            throw SyncError.networkError("Invalid URL: \(serverUrl)\(endpoint)")
        }
        return url
    }

    /// Fetches and decodes `T`, also returning the server's `X-Total-Count` header value if present.
    private func fetchFromServerWithTotalCount<T: Decodable>(_ type: T.Type, endpoint: String) async throws -> (value: T, totalCount: Int?) {
        let url = try makeURL(endpoint: endpoint)
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            logger.error("HTTP \(statusCode) from \(endpoint): \(responseBody.prefix(500))")
            throw SyncError.networkError(SyncError.httpMessage(status: statusCode, body: data))
        }

        let decoder = makeWireDecoder()

        do {
            let value = try decoder.decode(type, from: data)
            let totalCount = httpResponse.value(forHTTPHeaderField: "X-Total-Count").flatMap { Int($0) }
            return (value, totalCount)
        } catch {
            // Log the raw response for debugging
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            logger.error("JSON decode error for \(endpoint): \(error)")
            logger.error("Response was: \(responseBody.prefix(1000))")
            throw error
        }
    }
    
    /// JSON encoder whose dates match the server's wire contract: `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` (UTC,
    /// millisecond precision). NOTE: `JSONEncoder.dateEncodingStrategy = .iso8601` drops fractional
    /// seconds — uploads were floored to whole seconds while the local copy and the server's echo keep
    /// milliseconds, so the reconciler saw local as newer on every sync and re-uploaded forever. This
    /// is the inverse of the decode path in `fetchFromServerWithTotalCount`, which prefers `.SSS'Z'`.
    private func makeWireEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(SyncWireDate.string(from: date))
        }
        return encoder
    }

    /// The decode-side counterpart of `makeWireEncoder`: dates parse through `SyncWireDate`, which
    /// prefers the canonical `.SSS'Z'` form and tolerates the known server/GRDB variants. Shared by
    /// every response-body decode so the two directions can't drift.
    private func makeWireDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            guard let date = SyncWireDate.date(from: dateString) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
            }
            return date
        }
        return decoder
    }

    /// Header sent by the force re-sync-to-server paths on every overwrite. The server doesn't read
    /// it yet; it exists so a future server-side "reject writes with an older lastModifiedDate"
    /// guard (planned for web editing) has a way to recognize a deliberate mirror-this-device push
    /// and accept it anyway. Harmless today — unknown headers are ignored.
    public static let forceWriteHeader = "X-Salty-Force"

    private func postToServer<T: Encodable>(_ object: T, endpoint: String, force: Bool = false) async throws {
        let url = try makeURL(endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if force { request.setValue("1", forHTTPHeaderField: Self.forceWriteHeader) }
        addAuthHeader(to: &request)

        let encoder = makeWireEncoder()
        request.httpBody = try encoder.encode(object)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("POST to \(endpoint) failed HTTP \(statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
            throw SyncError.uploadFailed(SyncError.httpMessage(status: statusCode, body: data))
        }
    }
    
    private func putToServer<T: Encodable>(_ object: T, endpoint: String, force: Bool = false) async throws {
        let url = try makeURL(endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if force { request.setValue("1", forHTTPHeaderField: Self.forceWriteHeader) }
        addAuthHeader(to: &request)

        let encoder = makeWireEncoder()
        request.httpBody = try encoder.encode(object)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("PUT to \(endpoint) failed HTTP \(statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
            throw SyncError.uploadFailed(SyncError.httpMessage(status: statusCode, body: data))
        }
    }
    
    private func deleteOnServer(endpoint: String) async throws {
        guard let url = URL(string: "\(serverUrl)\(endpoint)") else {
            throw SyncError.uploadFailed("Invalid URL for DELETE: \(endpoint)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            throw SyncError.uploadFailed("DELETE to \(endpoint) failed")
        }
    }
    
    private func checkExists(endpoint: String) async throws -> Bool {
        guard let url = URL(string: "\(serverUrl)\(endpoint)") else {
            logger.warning("Invalid URL for checkExists: \(self.serverUrl)\(endpoint)")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        addAuthHeader(to: &request)
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            
            return httpResponse.statusCode == 200
        } catch {
            // Network errors shouldn't necessarily mean "doesn't exist"
            // Log and return false to trigger upload attempt
            logger.warning("checkExists failed for \(endpoint): \(error.localizedDescription)")
            return false
        }
    }

}
