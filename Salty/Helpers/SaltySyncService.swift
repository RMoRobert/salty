//
//  SaltySyncService.swift
//  Salty
//
//  Created by Robert on 1/24/26.

//  Handles bidirectional sync between local SQLite database and Salty Server (Java).
//

import Foundation
import SQLiteData
import OSLog
import UUIDV7
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
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

    /// True between the user asking to cancel and the sync unwinding. Drives the "Cancelling…" button state.
    private(set) var isCancelling = false

    /// Whether the sync currently running can be cancelled. False when idle, and false during a force re-sync.
    var isCancellable: Bool { currentSyncTask != nil }

    private var serverUrl: String {
        UserDefaults.standard.string(forKey: "serverUrl") ?? ""
    }
    
    private var serverEnabled: Bool {
        UserDefaults.standard.bool(forKey: "serverUse")
    }
    
    // MARK: - Authentication Properties
    
    /// Username for server authentication
    var serverUsername: String {
        get { UserDefaults.standard.string(forKey: "serverUsername") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "serverUsername") }
    }
    
    /// Password for server authentication (stored securely in Keychain)
    var serverPassword: String {
        get { KeychainHelper.shared.getPassword() }
        set { KeychainHelper.shared.savePassword(newValue) }
    }
    
    /// Cached JWT token (stored securely in Keychain)
    private var jwtToken: String? {
        get { KeychainHelper.shared.getJwtToken() }
        set { KeychainHelper.shared.saveJwtToken(newValue) }
    }
    
    /// Token expiration date (stored in UserDefaults - not sensitive)
    private var tokenExpirationDate: Date? {
        get { UserDefaults.standard.object(forKey: "serverTokenExpiration") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "serverTokenExpiration") }
    }
    
    /// Whether we have valid credentials configured
    var hasCredentials: Bool {
        !serverUsername.isEmpty && !serverPassword.isEmpty
    }
    
    /// Whether the current token is valid (exists and not expired)
    private var hasValidToken: Bool {
        guard let token = jwtToken, !token.isEmpty,
              let expiration = tokenExpirationDate else {
            return false
        }
        // Consider token invalid if it expires within the next minute
        return expiration > Date().addingTimeInterval(60)
    }
    
    /// Unique device ID for sync tracking (generated once, persisted)
    private var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: "syncDeviceId") {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "syncDeviceId")
        logger.info("Generated new device ID: \(newId)")
        return newId
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
    
    /// `session` defaults to `.shared` for the app singleton; tests inject a stubbed session.
    init(session: URLSession = .shared) {
        self.session = session
        // Restore the last sync time from a previous run. Assignment in `init` doesn't fire `didSet`, so
        // this doesn't write the value straight back.
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncDateKey) as? Date
    }
    
    // MARK: - Authentication Methods
    
    /// Login to the server and get a JWT token
    func login() async throws {
        guard !serverUsername.isEmpty, !serverPassword.isEmpty else {
            throw SyncError.authenticationFailed("Username and password are required")
        }
        
        guard let url = URL(string: "\(serverUrl)/api/auth/login") else {
            throw SyncError.authenticationFailed("Invalid server URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let credentials = ["username": serverUsername, "password": serverPassword]
        request.httpBody = try JSONEncoder().encode(credentials)
        
        logger.info("Attempting login for user: \(self.serverUsername)")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.authenticationFailed("Invalid response from server")
        }
        
        if httpResponse.statusCode == 401 {
            throw SyncError.authenticationFailed("Invalid username or password")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            logger.error("Login failed HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
            throw SyncError.authenticationFailed(SyncError.httpMessage(status: httpResponse.statusCode, body: data))
        }
        
        // Parse response
        struct AuthResponse: Codable {
            let token: String
            let username: String
            let expiresIn: Int  // milliseconds
        }
        
        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        
        // Store token and calculate expiration
        jwtToken = authResponse.token
        tokenExpirationDate = Date().addingTimeInterval(Double(authResponse.expiresIn) / 1000.0)
        
        logger.info("Login successful for user: \(authResponse.username), token expires in \(authResponse.expiresIn / 1000 / 60 / 60) hours")
    }
    
    /// Ensure we have a valid token, logging in if necessary
    private func ensureAuthenticated() async throws {
        if !hasValidToken {
            logger.info("Token expired or missing, logging in...")
            try await login()
        }
    }
    
    /// Clear stored authentication data
    func logout() {
        jwtToken = nil
        tokenExpirationDate = nil
        logger.info("Logged out, cleared JWT token")
    }
    
    /// Add authorization header to a request
    private func addAuthHeader(to request: inout URLRequest) {
        if let token = jwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    // MARK: - Public Sync Methods
    
    /// Performs a full bidirectional sync with the server.
    ///
    /// How soon after a successful sync another may start. Short enough that a deliberate re-sync never
    /// feels blocked (and Settings' Sync Now bypasses it entirely), long enough that a pull-to-refresh
    /// landing on top of an automatic sync, or an accidental double-trigger, costs the server nothing.
    nonisolated static let minimumSyncInterval: TimeInterval = 30

    /// Whether a new sync should be skipped because one finished moments ago. Pure and injectable (`now`)
    /// so the boundaries are unit-testable. A negative elapsed time means the clock moved backwards
    /// (time zone change, manual clock edit); sync rather than refuse based on a nonsense interval.
    nonisolated static func shouldThrottleSync(lastSuccessfulSync: Date?, now: Date = Date(), force: Bool) -> Bool {
        guard !force, let lastSuccessfulSync else { return false }
        let elapsed = now.timeIntervalSince(lastSuccessfulSync)
        return elapsed >= 0 && elapsed < minimumSyncInterval
    }

    /// The steps run in their own task, registered as `currentSyncTask`, so `cancelSync()` can stop a sync
    /// no matter which caller started it (Settings' "Sync Now", auto-sync, or the failure banner's Retry).
    /// Cancelling is safe at any point: each transfer is individually atomic (one request per recipe/image,
    /// one transaction per local write) and the server only advances this device's last-sync timestamp in
    /// the final `completeSyncOnServer()`, so a cancelled sync just leaves the rest for the next run --
    /// exactly what already happens when the connection drops partway through.
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
        currentSyncTask.cancel()
    }

    /// The sync steps themselves. `syncNow()` owns the `isSyncing`/cancellation bookkeeping around this.
    private func performFullSync() async throws {
        do {
            // Step 0: Authenticate with server
            logger.info("Step 0: Authenticating...")
            syncProgress.currentStep = "Authenticating..."
            try await ensureAuthenticated()
            logger.info("Authentication successful")
            
            // Step 1: Register device with server
            logger.info("Step 1: Registering device...")
            syncProgress.currentStep = "Registering device..."
            let deviceInfo = try await registerDevice()
            logger.info("Device registered: \(self.deviceId), isFirstSync: \(deviceInfo.isFirstSync)")
            
            // Step 2: Sync courses (with deletion detection)
            logger.info("Step 2: Syncing courses...")
            syncProgress.currentStep = "Syncing courses..."
            try await syncCoursesWithDeletions(deviceInfo: deviceInfo)
            logger.info("Courses synced successfully")
            
            // Step 3: Sync categories (with deletion detection)
            logger.info("Step 3: Syncing categories...")
            syncProgress.currentStep = "Syncing categories..."
            try await syncCategoriesWithDeletions(deviceInfo: deviceInfo)
            logger.info("Categories synced successfully")
            
            // Step 4: Sync tags (with deletion detection)
            logger.info("Step 4: Syncing tags...")
            syncProgress.currentStep = "Syncing tags..."
            try await syncTagsWithDeletions(deviceInfo: deviceInfo)
            logger.info("Tags synced successfully")
            
            // Step 4b: Sync shopping lists (with deletion detection)
            logger.info("Step 4b: Syncing shopping lists...")
            syncProgress.currentStep = "Syncing shopping lists..."
            try await syncShoppingListsWithDeletions(deviceInfo: deviceInfo)
            logger.info("Shopping lists synced successfully")

            // Step 5: Sync recipes (with deletion detection)
            logger.info("Step 5: Syncing recipes...")
            syncProgress.currentStep = "Syncing recipes..."
            try await syncRecipesWithDeletions(deviceInfo: deviceInfo)
            logger.info("Recipes synced successfully")
            
            // Step 6: Sync images
            logger.info("Step 6: Syncing images...")
            syncProgress.currentStep = "Syncing images..."
            try await syncImages()
            logger.info("Images synced successfully")

            // Step 6b: fold any same-named courses/categories/tags into one row
            syncProgress.currentStep = "Tidying categories, courses, and tags..."
            await consolidateDuplicateLibraryItems()

            // Step 7: Mark sync complete on server. Explicitly checked first: completing marks this device
            // caught up, so it must never run after a cancel that skipped work (step 6b doesn't throw).
            try Task.checkCancellation()
            logger.info("Step 7: Completing sync...")
            syncProgress.currentStep = "Completing sync..."
            try await completeSyncOnServer()
            logger.info("Sync marked complete on server")

            lastSyncDate = Date()
            syncProgress.currentStep = "Sync complete!"
            logger.info("Sync completed successfully")

        } catch {
            if SyncError.isCancellation(error) {
                logger.info("Sync cancelled at step '\(self.syncProgress.currentStep)'")
                syncProgress.currentStep = "Sync cancelled"
                lastSyncError = nil  // a cancel is a user action, not a failure to report
                throw SyncError.cancelled
            }
            lastSyncError = friendlySyncMessage(error)
            logger.error("Sync failed at step '\(self.syncProgress.currentStep)': \(error)")
            throw error
        }
    }
    
    /// Force a full re-sync: delete *all* local recipes/courses/categories/tags and re-download
    /// everything from the server. One-way (server -> local); performs no uploads and no server
    /// deletions, so it's a safe recovery path (e.g. after local corruption or stale test data).
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
            syncProgress.currentStep = "Authenticating..."
            try await ensureAuthenticated()
            _ = try await registerDevice() // ensure the device is registered (state is otherwise ignored)

            // Fetch the full server state first (so a failed download leaves local data intact).
            syncProgress.currentStep = "Downloading from server..."
            let serverCourses = try await fetchListFromServer(ServerCourse.self, endpoint: "/api/courses")
            let serverCategories = try await fetchListFromServer(ServerCategory.self, endpoint: "/api/categories")
            let serverTags = try await fetchListFromServer(ServerTag.self, endpoint: "/api/tags")
            let serverShoppingLists = try await fetchListFromServer(ServerShoppingList.self, endpoint: "/api/shoppingLists")
            let serverRecipes = try await fetchRecipeDeltaPaged(modifiedSince: nil) // nil → all recipes

            // Wipe the local database + local image files.
            syncProgress.currentStep = "Clearing local data..."
            let oldImageFilenames = try await database.read { db in
                try Recipe.fetchAll(db).compactMap { $0.imageFilename }
            }
            try await database.write { db in
                try RecipeCategory.delete().execute(db)
                try RecipeTag.delete().execute(db)
                try Recipe.delete().execute(db)
                try Course.delete().execute(db)
                try Category.delete().execute(db)
                try Tag.delete().execute(db)
                try ShoppingList.delete().execute(db)
            }
            for filename in oldImageFilenames {
                RecipeImageManager.shared.deleteImage(filename: filename)
            }

            // Shopping-list rows land with their sync bookkeeping (revision + snapshot) so the next
            // regular sync starts revision-based instead of legacy-seeding every row.
            let shoppingListRows = try serverShoppingLists.map { try syncedLocalRow(for: $0) }

            // Insert courses/categories/tags first -- downloadRecipe only links categories/tags that already exist locally.
            try await database.write { db in
                for c in serverCourses {
                    try Course.insert { Course(id: c.id, name: c.name ?? "", lastModifiedDate: c.lastModifiedDate ?? Date()) }.execute(db)
                }
                for c in serverCategories {
                    try Category.insert { Category(id: c.id, name: c.name ?? "", lastModifiedDate: c.lastModifiedDate ?? Date()) }.execute(db)
                }
                for t in serverTags {
                    try Tag.insert { Tag(id: t.id, name: t.name ?? "", lastModifiedDate: t.lastModifiedDate ?? Date()) }.execute(db)
                }
                for row in shoppingListRows {
                    try ShoppingList.insert { row }.execute(db)
                }
            }
            syncProgress.itemsDownloaded += serverCourses.count + serverCategories.count + serverTags.count + serverShoppingLists.count

            // Download recipes (marking them downloaded so syncImages pulls their images).
            syncProgress.currentStep = "Downloading recipes..."
            for serverRecipe in serverRecipes {
                try await downloadRecipe(serverRecipe)
                syncProgress.itemsDownloaded += 1
                syncProgress.downloadedRecipeIds.insert(serverRecipe.id)
            }

            // Images: local files were wiped, so this only downloads (nothing to upload).
            syncProgress.currentStep = "Downloading images..."
            try await syncImages()

            // The server's own vocabulary can contain same-named rows; don't rebuild the local
            // library with them. The next ordinary sync propagates the resulting deletions.
            syncProgress.currentStep = "Tidying categories, courses, and tags..."
            await consolidateDuplicateLibraryItems()

            try await completeSyncOnServer()
            lastSyncDate = Date()
            syncProgress.currentStep = "Full re-sync complete!"
            logger.info("Force full re-sync complete: \(serverRecipes.count) recipes")
        } catch {
            lastSyncError = friendlySyncMessage(error)
            logger.error("Force full re-sync failed at '\(self.syncProgress.currentStep)': \(error)")
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
            syncProgress.currentStep = "Authenticating..."
            try await ensureAuthenticated()
            _ = try await registerDevice() // ensure the device is registered (state is otherwise ignored)

            // Snapshot the current server inventory so we know which items to overwrite vs. delete.
            syncProgress.currentStep = "Inspecting server..."
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

            let serverCourseIds = Set(serverCourses.map { $0.id })
            let serverCategoryIds = Set(serverCategories.map { $0.id })
            let serverTagIds = Set(serverTags.map { $0.id })
            let serverShoppingListsById = Dictionary(serverShoppingLists.map { ($0.id, $0) }, uniquingKeysWith: { $1 })

            // Push courses/categories/tags first. Recipes link them by id, which must already exist
            // server-side. Update items the server already has, create the rest.
            syncProgress.currentStep = "Uploading to server..."
            for c in localCourses {
                if serverCourseIds.contains(c.id) {
                    try await putToServer(c, endpoint: "/api/courses/\(c.id)")
                } else {
                    try await postToServer(c, endpoint: "/api/courses")
                }
            }
            for c in localCategories {
                if serverCategoryIds.contains(c.id) {
                    try await putToServer(c, endpoint: "/api/categories/\(c.id)")
                } else {
                    try await postToServer(c, endpoint: "/api/categories")
                }
            }
            for t in localTags {
                if serverTagIds.contains(t.id) {
                    try await putToServer(t, endpoint: "/api/tags/\(t.id)")
                } else {
                    try await postToServer(t, endpoint: "/api/tags")
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
            syncProgress.itemsUploaded += localCourses.count + localCategories.count + localTags.count + localShoppingLists.count

            // Push recipes (uploadRecipe overwrites existing or creates new as needed).
            syncProgress.currentStep = "Uploading recipes..."
            for recipe in localRecipes {
                try await uploadRecipe(recipe)
                syncProgress.itemsUploaded += 1
                syncProgress.uploadedRecipeIds.insert(recipe.id)
            }

            // Remove anything on the server that no longer exists locally (it was deleted from the
            // source of truth). Recipes first, then vocab they may reference.
            syncProgress.currentStep = "Removing stale server data..."
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
            syncProgress.currentStep = "Uploading images..."
            try await syncImages()

            try await completeSyncOnServer()
            lastSyncDate = Date()
            syncProgress.currentStep = "Full re-sync complete!"
            logger.info("Force full re-sync to server complete: \(localRecipes.count) recipes")
        } catch {
            lastSyncError = friendlySyncMessage(error)
            logger.error("Force full re-sync to server failed at '\(self.syncProgress.currentStep)': \(error)")
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
        if serverItemCount == 0 && pendingLocalDeletions > 0 {
            logger.error("Skipping \(pendingLocalDeletions) local \(entity) deletion(s): the server returned an empty list, which likely indicates an incomplete response rather than real deletions.")
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
            if !toDeleteLocally.isEmpty {
                logger.info("Deleted \(toDeleteLocally.count) shopping list(s) locally (were deleted on server)")
            }
        }

        for s in serverLists where !localIds.contains(s.id) {
            try Task.checkCancellation()
            // Server-only row: new to us, or deleted here. No tombstones for lists, so the watermark
            // decides — except a failed If-Match delete proves the row changed, and change wins.
            let serverDate = (s.lastModifiedDate ?? .distantPast).roundedToWireMillis
            if deviceInfo.isFirstSync || deviceInfo.lastSyncDate == nil || serverDate > deviceInfo.lastSyncDate! {
                try await downloadShoppingList(s)
            } else {
                switch try await deleteShoppingListOnServer(id: s.id, expectedRevision: s.revision) {
                case .deleted:
                    logger.info("Deleted shopping list \(s.id) on server (was deleted locally)")
                case .conflict(let current):
                    try await downloadShoppingList(current)
                }
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
            syncProgress.itemsUploaded += 1
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
            conflictCopyId: UUID().uuidString,
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
                syncProgress.itemsUploaded += 1
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
            syncProgress.itemsUploaded += 1
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

    /// Writes a SERVER-agreed row: contents and sync bookkeeping move together, so the row lands
    /// already-clean with the server row itself as the snapshot.
    private func downloadShoppingList(_ server: ServerShoppingList) async throws {
        let row = try syncedLocalRow(for: server)
        try await database.write { db in
            try ShoppingList.upsert { row }.execute(db)
        }
        syncProgress.itemsDownloaded += 1
    }

    /// Records the server agreement after a successful UPLOAD without touching the row's contents:
    /// [accepted] is the server's response (our content + the revision it assigned).
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

    /// Today as "yyyy-MM-dd" (UTC), for conflict-copy labels — mirrors SaltyKMP's `nowDayStamp()`.
    /// nonisolated because it's pure (the enclosing class is @MainActor).
    nonisolated private static func dayStamp(_ date: Date = Date()) -> String {
        String(SyncWireDate.string(from: date).prefix(10))
    }

    // MARK: - Course Sync

    private func syncCoursesWithDeletions(deviceInfo: DeviceInfo) async throws {
        let serverCourses = try await fetchListFromServer(ServerCourse.self, endpoint: "/api/courses")
        let localCourses = try await database.read { db in
            try Course.fetchAll(db)
        }
        
        // uniquingKeysWith (not uniqueKeysWithValues) so a duplicate id in the server response
        // can't trap/crash the sync; keep the last occurrence.
        let serverCoursesById = Dictionary(serverCourses.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localCourseIds = Set(localCourses.map { $0.id })
        
        var toDeleteOnServer: [String] = []
        var toDeleteLocally: [String] = []
        
        // Process each local course
        for localCourse in localCourses {
            if let serverCourse = serverCoursesById[localCourse.id] {
                // Exists on both - compare timestamps for updates
                let serverDate = (serverCourse.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                let localDate = (localCourse.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                
                if localDate > serverDate {
                    try await putToServer(localCourse, endpoint: "/api/courses/\(localCourse.id)")
                    syncProgress.itemsUploaded += 1
                } else if serverDate > localDate {
                    let course = Course(id: serverCourse.id, name: serverCourse.name ?? "", lastModifiedDate: serverDate)
                    try await database.write { db in
                        try Course.upsert { course }.execute(db)
                    }
                    syncProgress.itemsDownloaded += 1
                }
            } else {
                // Only exists locally
                if deviceInfo.isFirstSync {
                    try await postToServer(localCourse, endpoint: "/api/courses")
                    syncProgress.itemsUploaded += 1
                } else if let lastSync = deviceInfo.lastSyncDate {
                    let localDate = (localCourse.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if localDate > lastSync {
                        try await postToServer(localCourse, endpoint: "/api/courses")
                        syncProgress.itemsUploaded += 1
                    } else {
                        toDeleteLocally.append(localCourse.id)
                    }
                } else {
                    try await postToServer(localCourse, endpoint: "/api/courses")
                    syncProgress.itemsUploaded += 1
                }
            }
        }
        
        // Process courses only on server
        for serverCourse in serverCourses {
            if !localCourseIds.contains(serverCourse.id) {
                if deviceInfo.isFirstSync {
                    let course = Course(id: serverCourse.id, name: serverCourse.name ?? "", lastModifiedDate: serverCourse.lastModifiedDate ?? Date())
                    try await database.write { db in
                        try Course.insert { course }.execute(db)
                    }
                    syncProgress.itemsDownloaded += 1
                } else if let lastSync = deviceInfo.lastSyncDate {
                    let serverDate = (serverCourse.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if serverDate > lastSync {
                        let course = Course(id: serverCourse.id, name: serverCourse.name ?? "", lastModifiedDate: serverDate)
                        try await database.write { db in
                            try Course.insert { course }.execute(db)
                        }
                        syncProgress.itemsDownloaded += 1
                    } else {
                        toDeleteOnServer.append(serverCourse.id)
                    }
                } else {
                    let course = Course(id: serverCourse.id, name: serverCourse.name ?? "", lastModifiedDate: serverCourse.lastModifiedDate ?? Date())
                    try await database.write { db in
                        try Course.insert { course }.execute(db)
                    }
                    syncProgress.itemsDownloaded += 1
                }
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
        
        // Delete on server
        for id in toDeleteOnServer {
            try await deleteOnServer(endpoint: "/api/courses/\(id)")
            logger.info("Deleted course \(id) on server (was deleted locally)")
        }
    }
    
    // MARK: - Duplicate library items

    /// Folds same-named courses/categories/tags into a single row at the end of a sync.
    ///
    /// Vocabulary rows are reconciled by **id**, never by name (see `syncCoursesWithDeletions` and
    /// its siblings), so two devices that each create "Vegan" -- or two installs that each ran the
    /// migration-0002 seed and got their own ids for "Breads", "Main", … -- end up with two rows
    /// that sync then replicates faithfully, forever. Nothing upstream can notice: to the server
    /// they are simply two different rows that happen to share a name.
    ///
    /// The merge itself re-points every recipe before deleting the duplicate, so no recipe loses a
    /// classification, and the survivor is chosen by **id** rather than by recipe count: counts
    /// differ from device to device, and only an id-based rule makes every device pick the same
    /// winner. Once they agree, the loser's deletion propagates on the following sync (its server
    /// timestamp is by then older than the watermark) and the library converges.
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
        let localCategories = try await database.read { db in
            try Category.fetchAll(db)
        }
        
        let serverCategoriesById = Dictionary(serverCategories.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localCategoryIds = Set(localCategories.map { $0.id })
        
        var toDeleteOnServer: [String] = []
        var toDeleteLocally: [String] = []
        
        // Process each local category
        for localCategory in localCategories {
            if let serverCategory = serverCategoriesById[localCategory.id] {
                // Exists on both - compare timestamps for updates
                let serverDate = (serverCategory.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                let localDate = (localCategory.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                
                if localDate > serverDate {
                    try await putToServer(localCategory, endpoint: "/api/categories/\(localCategory.id)")
                    syncProgress.itemsUploaded += 1
                } else if serverDate > localDate {
                    let category = Category(id: serverCategory.id, name: serverCategory.name ?? "", lastModifiedDate: serverDate)
                    try await database.write { db in
                        try Category.upsert { category }.execute(db)
                    }
                    syncProgress.itemsDownloaded += 1
                }
            } else {
                // Only exists locally
                if deviceInfo.isFirstSync {
                    try await postToServer(localCategory, endpoint: "/api/categories")
                    syncProgress.itemsUploaded += 1
                } else if let lastSync = deviceInfo.lastSyncDate {
                    let localDate = (localCategory.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if localDate > lastSync {
                        try await postToServer(localCategory, endpoint: "/api/categories")
                        syncProgress.itemsUploaded += 1
                    } else {
                        toDeleteLocally.append(localCategory.id)
                    }
                } else {
                    try await postToServer(localCategory, endpoint: "/api/categories")
                    syncProgress.itemsUploaded += 1
                }
            }
        }
        
        // Process categories only on server
        for serverCategory in serverCategories {
            if !localCategoryIds.contains(serverCategory.id) {
                if deviceInfo.isFirstSync {
                    let category = Category(id: serverCategory.id, name: serverCategory.name ?? "", lastModifiedDate: serverCategory.lastModifiedDate ?? Date())
                    try await database.write { db in
                        try Category.insert { category }.execute(db)
                    }
                    syncProgress.itemsDownloaded += 1
                } else if let lastSync = deviceInfo.lastSyncDate {
                    let serverDate = (serverCategory.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if serverDate > lastSync {
                        let category = Category(id: serverCategory.id, name: serverCategory.name ?? "", lastModifiedDate: serverDate)
                        try await database.write { db in
                            try Category.insert { category }.execute(db)
                        }
                        syncProgress.itemsDownloaded += 1
                    } else {
                        toDeleteOnServer.append(serverCategory.id)
                    }
                } else {
                    let category = Category(id: serverCategory.id, name: serverCategory.name ?? "", lastModifiedDate: serverCategory.lastModifiedDate ?? Date())
                    try await database.write { db in
                        try Category.insert { category }.execute(db)
                    }
                    syncProgress.itemsDownloaded += 1
                }
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
        
        // Delete on server
        for id in toDeleteOnServer {
            try await deleteOnServer(endpoint: "/api/categories/\(id)")
            logger.info("Deleted category \(id) on server (was deleted locally)")
        }
    }
    
    // MARK: - Tag Sync
    
    private func syncTagsWithDeletions(deviceInfo: DeviceInfo) async throws {
        let serverTags = try await fetchListFromServer(ServerTag.self, endpoint: "/api/tags")
        let localTags = try await database.read { db in
            try Tag.fetchAll(db)
        }
        
        let serverTagsById = Dictionary(serverTags.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localTagIds = Set(localTags.map { $0.id })
        
        var toDeleteOnServer: [String] = []
        var toDeleteLocally: [String] = []
        
        // Process each local tag
        for localTag in localTags {
            if let serverTag = serverTagsById[localTag.id] {
                // Exists on both - compare timestamps for updates
                let serverDate = (serverTag.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                let localDate = (localTag.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                
                if localDate > serverDate {
                    try await putToServer(localTag, endpoint: "/api/tags/\(localTag.id)")
                    syncProgress.itemsUploaded += 1
                } else if serverDate > localDate {
                    let tag = Tag(id: serverTag.id, name: serverTag.name ?? "", lastModifiedDate: serverDate)
                    try await database.write { db in
                        try Tag.upsert { tag }.execute(db)
                    }
                    syncProgress.itemsDownloaded += 1
                }
            } else {
                // Only exists locally
                if deviceInfo.isFirstSync {
                    try await postToServer(localTag, endpoint: "/api/tags")
                    syncProgress.itemsUploaded += 1
                } else if let lastSync = deviceInfo.lastSyncDate {
                    let localDate = (localTag.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if localDate > lastSync {
                        try await postToServer(localTag, endpoint: "/api/tags")
                        syncProgress.itemsUploaded += 1
                    } else {
                        toDeleteLocally.append(localTag.id)
                    }
                } else {
                    try await postToServer(localTag, endpoint: "/api/tags")
                    syncProgress.itemsUploaded += 1
                }
            }
        }
        
        // Process tags only on server
        for serverTag in serverTags {
            if !localTagIds.contains(serverTag.id) {
                if deviceInfo.isFirstSync {
                    let tag = Tag(id: serverTag.id, name: serverTag.name ?? "", lastModifiedDate: serverTag.lastModifiedDate ?? Date())
                    try await database.write { db in
                        try Tag.insert { tag }.execute(db)
                    }
                    syncProgress.itemsDownloaded += 1
                } else if let lastSync = deviceInfo.lastSyncDate {
                    let serverDate = (serverTag.lastModifiedDate ?? Date.distantPast).roundedToWireMillis
                    if serverDate > lastSync {
                        let tag = Tag(id: serverTag.id, name: serverTag.name ?? "", lastModifiedDate: serverDate)
                        try await database.write { db in
                            try Tag.insert { tag }.execute(db)
                        }
                        syncProgress.itemsDownloaded += 1
                    } else {
                        toDeleteOnServer.append(serverTag.id)
                    }
                } else {
                    let tag = Tag(id: serverTag.id, name: serverTag.name ?? "", lastModifiedDate: serverTag.lastModifiedDate ?? Date())
                    try await database.write { db in
                        try Tag.insert { tag }.execute(db)
                    }
                    syncProgress.itemsDownloaded += 1
                }
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
        
        // Delete on server
        for id in toDeleteOnServer {
            try await deleteOnServer(endpoint: "/api/tags/\(id)")
            logger.info("Deleted tag \(id) on server (was deleted locally)")
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
        
        return DeviceInfo(deviceId: deviceId, lastSyncDate: lastSyncDate, isFirstSync: isFirstSync)
    }
    
    /// Mark sync as complete on server. Internal (not private) so its non-2xx throw is unit-testable.
    func completeSyncOnServer() async throws {
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
        let manifest = try await fetchManifest()

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
        let localEntries = localRecipes.map {
            RecipeSyncReconciler.Entry(id: $0.id, lastModified: $0.lastModifiedDate.roundedToWireMillis)
        }
        let serverEntries = manifest.map {
            RecipeSyncReconciler.Entry(id: $0.id, lastModified: ($0.lastModifiedDate ?? Date.distantPast).roundedToWireMillis)
        }
        let plan = RecipeSyncReconciler.plan(
            local: localEntries,
            server: serverEntries,
            isFirstSync: deviceInfo.isFirstSync,
            lastSyncDate: deviceInfo.lastSyncDate
        )

        logger.info("Sync plan: \(plan.toUpload.count) upload, \(plan.toDownload.count) download, \(plan.toDeleteLocally.count) delete-local, \(plan.toDeleteOnServer.count) delete-server (manifest \(manifest.count), delta \(deltaRecipes.count))")

        // 5. Uploads. Each is a single request, so a cancel between them just leaves the rest for next time.
        for recipeId in plan.toUpload {
            try Task.checkCancellation()
            guard let localRecipe = localRecipesById[recipeId] else { continue }
            try await uploadRecipe(localRecipe)
            syncProgress.itemsUploaded += 1
            syncProgress.uploadedRecipeIds.insert(recipeId)
        }

        // 6. Downloads — use the delta body when present, otherwise fetch that single recipe (covers the
        //    rare case where the server copy is newer than local but predates lastSync).
        for recipeId in plan.toDownload {
            try Task.checkCancellation()
            let serverRecipe: ServerRecipe
            if let body = deltaById[recipeId] {
                serverRecipe = body
            } else {
                serverRecipe = try await fetchRecipeById(recipeId)
            }
            try await downloadRecipe(serverRecipe)
            syncProgress.itemsDownloaded += 1
            syncProgress.downloadedRecipeIds.insert(recipeId)
        }

        // 7. Deletions — local deletes are guarded against empty-response wipes using the COMPLETE
        //    manifest count, and batched in one transaction.
        if serverResponseAllowsLocalDeletions(serverItemCount: manifest.count, pendingLocalDeletions: plan.toDeleteLocally.count, entity: "recipe") {
            for recipeId in plan.toDeleteLocally {
                logger.info("Deleting recipe \(recipeId) locally (was deleted on another device)")
                if let recipe = localRecipesById[recipeId], let filename = recipe.imageFilename {
                    RecipeImageManager.shared.deleteImage(filename: filename)
                }
            }
            try await database.write { db in
                for recipeId in plan.toDeleteLocally {
                    _ = try Recipe.deleteOne(db, key: recipeId)
                }
            }
            syncProgress.itemsDownloaded += plan.toDeleteLocally.count // Count as sync actions
        }

        // Delete recipes on server that were deleted locally.
        if !plan.toDeleteOnServer.isEmpty {
            logger.info("Deleting \(plan.toDeleteOnServer.count) recipe(s) on server (were deleted locally)")
            try await deleteRecipesOnServer(recipeIds: plan.toDeleteOnServer)
        }

        if !plan.toDeleteLocally.isEmpty || !plan.toDeleteOnServer.isEmpty {
            logger.info("Deletion sync: \(plan.toDeleteLocally.count) deleted locally, \(plan.toDeleteOnServer.count) deleted on server")
        }
    }
    
    /// Delete recipes on the server. Internal (not private) so its non-2xx throw is unit-testable.
    func deleteRecipesOnServer(recipeIds: [String]) async throws {
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
    
    private func uploadRecipe(_ recipe: Recipe) async throws {
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
            try await putToServer(serverRecipe, endpoint: "/api/recipes/\(recipe.id)")
        } else {
            try await postToServer(serverRecipe, endpoint: "/api/recipes")
        }
        
        logger.info("Uploaded recipe: \(recipe.name) with \(categoryIds.count) categories (IDs: \(categoryIds)) and \(tagIds.count) tags (IDs: \(tagIds))")
    }
    
    private func downloadRecipe(_ serverRecipe: ServerRecipe) async throws {
        let recipe = serverRecipe.toLocalRecipe()

        logger.info("downloadRecipe called for '\(serverRecipe.name)' with categoryIds: \(serverRecipe.categoryIds ?? []), tagIds: \(serverRecipe.tagIds ?? [])")

        try await database.write { db in
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
                        id: "\(recipe.id)_\(categoryId)",
                        recipeId: recipe.id,
                        categoryId: categoryId
                    )
                    try RecipeCategory.insert { rc }.execute(db)
                    logger.debug("Inserted RecipeCategory: recipe=\(recipe.id), category=\(categoryId)")
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
                        id: "\(recipe.id)_\(tagId)",
                        recipeId: recipe.id,
                        tagId: tagId
                    )
                    try RecipeTag.insert { rt }.execute(db)
                    logger.debug("Inserted RecipeTag: recipe=\(recipe.id), tag=\(tagId)")
                }
            }
        }
        logger.info("Downloaded recipe complete: \(recipe.name)")
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
                    if let localFile, let data = RecipeImageManager.shared.loadImage(filename: localFile) {
                        try await uploadImage(data, for: id, imageDate: local?.lastModifiedImageDate)
                        syncProgress.imagesUploaded += 1
                    } else if serverFile != nil {
                        try await deleteServerImage(for: id, imageDate: local?.lastModifiedImageDate)
                        syncProgress.imagesUploaded += 1
                    }
                } else if serverDate > localDate {
                    // Server image change wins → pull it (or apply its removal) locally.
                    if let serverFile {
                        try await downloadImage(filename: serverFile, for: id, imageDate: server?.lastModifiedImageDate)
                        syncProgress.imagesDownloaded += 1
                    } else if localFile != nil {
                        try await clearLocalImage(for: id, imageDate: server?.lastModifiedImageDate)
                        syncProgress.imagesDownloaded += 1
                    }
                } else {
                    // Equal image dates: propagate an image the other side never received, or recover a local
                    // image whose file is missing. (A removal stamps a fresh, unequal date — equality is never
                    // a removal.)
                    if let serverFile, localFile == nil {
                        try await downloadImage(filename: serverFile, for: id, imageDate: server?.lastModifiedImageDate)
                        syncProgress.imagesDownloaded += 1
                    } else if let localFile, serverFile == nil,
                              let data = RecipeImageManager.shared.loadImage(filename: localFile) {
                        try await uploadImage(data, for: id, imageDate: local?.lastModifiedImageDate)
                        syncProgress.imagesUploaded += 1
                    } else if let serverFile, let localFile,
                              RecipeImageManager.shared.loadImage(filename: localFile) == nil {
                        try await downloadImage(filename: serverFile, for: id, imageDate: server?.lastModifiedImageDate)
                        syncProgress.imagesDownloaded += 1
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

        logger.info("Image sync: \(self.syncProgress.imagesUploaded) uploaded, \(self.syncProgress.imagesDownloaded) downloaded, \(imageErrors.count) failed")
        if !imageErrors.isEmpty, syncProgress.imagesUploaded == 0, syncProgress.imagesDownloaded == 0 {
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

        // Prepare image data (converts HEIC to JPEG if needed)
        let prepared = prepareImageForUpload(imageData)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.\(prepared.extension)\"\r\n".data(using: .utf8)!)
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
    
    /// Detects image type from file header bytes and returns converted data if needed
    private func prepareImageForUpload(_ data: Data) -> (data: Data, mimeType: String, extension: String) {
        guard data.count >= 8 else {
            return (data, "image/jpeg", "jpg")
        }
        
        let bytes = [UInt8](data.prefix(8))
        
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return (data, "image/png", "png")
        }
        
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return (data, "image/jpeg", "jpg")
        }
        
        // GIF: 47 49 46 38
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
            return (data, "image/gif", "gif")
        }
        
        // WebP: 52 49 46 46 ... 57 45 42 50 - convert to JPEG for broader compatibility
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 {
            if let jpegData = convertToJPEG(data) {
                logger.debug("Converted WebP image to JPEG")
                return (jpegData, "image/jpeg", "jpg")
            }
            // If conversion fails, send as WebP
            return (data, "image/webp", "webp")
        }
        
        // HEIC/HEIF: Check for 'ftyp' box - convert to JPEG
        if data.count >= 12 {
            let ftypBytes = [UInt8](data[4..<8])
            if ftypBytes[0] == 0x66 && ftypBytes[1] == 0x74 && ftypBytes[2] == 0x79 && ftypBytes[3] == 0x70 {
                // Get the brand to log what type of HEIC it is
                let brandBytes = [UInt8](data[8..<12])
                let brand = String(bytes: brandBytes, encoding: .ascii) ?? "unknown"
                logger.debug("Detected HEIC/HEIF image with brand: \(brand)")
                
                // Convert HEIC to PNG for Salty Server compatibility
                if let pngData = convertToPNG(data) {
                    logger.info("Converted HEIC image to PNG (\(data.count) bytes -> \(pngData.count) bytes)")
                    return (pngData, "image/png", "png")
                } else {
                    logger.error("Failed to convert HEIC image to PNG - image may not display on server")
                }
            }
        }
        
        // Unknown format - try to convert to JPEG
        let hexHeader = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug("Unknown image format, header: \(hexHeader), attempting JPEG conversion")
        
        if let jpegData = convertToJPEG(data) {
            logger.info("Converted unknown format to JPEG (\(data.count) bytes -> \(jpegData.count) bytes)")
            return (jpegData, "image/jpeg", "jpg")
        }
        
        // Fallback: send as-is - but log a warning since this may not work
        logger.warning("Could not convert image to JPEG, sending original data (\(data.count) bytes) - may not display correctly")
        return (data, "application/octet-stream", "bin")
    }
    
    /// Converts image data to JPEG format
    private func convertToJPEG(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            logger.warning("UIImage failed to load image data (\(data.count) bytes)")
            return nil
        }
        guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
            logger.warning("Failed to convert UIImage to JPEG")
            return nil
        }
        return jpegData
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            logger.warning("NSImage failed to load image data (\(data.count) bytes)")
            return nil
        }
        guard let tiffData = image.tiffRepresentation else {
            logger.warning("Failed to get TIFF representation from NSImage")
            return nil
        }
        guard let bitmap = NSBitmapImageRep(data: tiffData) else {
            logger.warning("Failed to create NSBitmapImageRep from TIFF data")
            return nil
        }
        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            logger.warning("Failed to create JPEG representation from bitmap")
            return nil
        }
        return jpegData
        #else
        logger.warning("No image conversion available on this platform")
        return nil
        #endif
    }
    
    /// Converts image data to PNG format
    private func convertToPNG(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            logger.warning("UIImage failed to load image data (\(data.count) bytes)")
            return nil
        }
        guard let pngData = image.pngData() else {
            logger.warning("Failed to convert UIImage to PNG")
            return nil
        }
        return pngData
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            logger.warning("NSImage failed to load image data (\(data.count) bytes)")
            return nil
        }
        guard let tiffData = image.tiffRepresentation else {
            logger.warning("Failed to get TIFF representation from NSImage")
            return nil
        }
        guard let bitmap = NSBitmapImageRep(data: tiffData) else {
            logger.warning("Failed to create NSBitmapImageRep from TIFF data")
            return nil
        }
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            logger.warning("Failed to create PNG representation from bitmap")
            return nil
        }
        return pngData
        #else
        logger.warning("No image conversion available on this platform")
        return nil
        #endif
    }
    
    /// Percent-encodes a server-supplied image filename as a SINGLE path component: unlike
    /// `.urlPathAllowed`, "/" is also encoded, so a hostile value can't traverse out of
    /// `/api/recipes/images/` and steer the authenticated request to another endpoint. Legit
    /// filenames are always `<recipeId>.<ext>`, which this encoding leaves untouched.
    /// Internal (not private) for unit testing; nonisolated because it's pure (the enclosing class is @MainActor).
    nonisolated static func encodedImagePathComponent(_ filename: String) -> String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return filename.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    /// Downloads image bytes and records the server's [imageDate] locally, so the next sync sees the local
    /// and server image timestamps as equal and doesn't re-transfer.
    /// [maxBytes] rejects an oversized (hostile or corrupt) response before it's written to disk/database;
    /// syncImages treats the throw as a per-recipe failure, so one bad image doesn't abort the whole sync.
    /// Internal (not private) so its failure-path throws are unit-testable; maxBytes is injectable so the
    /// cap can be tested without a multi-hundred-MB fixture.
    func downloadImage(filename: String, for recipeId: String, imageDate: Date?,
                       maxBytes: Int = ImportFileLimits.maxSyncImageDownloadBytes) async throws {
        // `filename` is server-controlled; percent-encode it and guard the URL so a malformed name
        // surfaces as a recoverable error instead of crashing the sync.
        guard let encodedFilename = Self.encodedImagePathComponent(filename),
              let url = URL(string: "\(serverUrl)/api/recipes/images/\(encodedFilename)") else {
            throw SyncError.downloadFailed("Invalid image URL for filename: \(filename)")
        }
        logger.debug("Downloading image from: \(url)")

        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.downloadFailed("No HTTP response for image download: \(filename)")
        }

        guard httpResponse.statusCode == 200 else {
            throw SyncError.downloadFailed("Image download failed for '\(filename)': \(SyncError.httpMessage(status: httpResponse.statusCode, body: data))")
        }

        guard data.count <= maxBytes else {
            throw SyncError.downloadFailed("Image '\(filename)' is \(data.count) bytes, over the \(maxBytes)-byte sync limit; skipping")
        }

        logger.debug("Downloaded image '\(filename)': \(data.count) bytes")

        // Save image locally and update recipe (filename + thumbnail + image timestamp together).
        if let result = RecipeImageManager.shared.saveImage(data, for: recipeId) {
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
        if let filename { RecipeImageManager.shared.deleteImage(filename: filename) }
        try await database.write { db in
            try db.execute(sql: """
                UPDATE recipe
                SET imageFilename = NULL, imageThumbnailData = NULL, lastModifiedImageDate = ?
                WHERE id = ?
                """,
                arguments: [imageDate, recipeId]
            )
        }
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

    private func postToServer<T: Encodable>(_ object: T, endpoint: String) async throws {
        let url = try makeURL(endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
    
    private func putToServer<T: Encodable>(_ object: T, endpoint: String) async throws {
        let url = try makeURL(endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

/// Canonical conversion between a `Date` and the Salty Server wire timestamp
/// (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` — UTC, millisecond precision). Centralized so the encode and decode
/// paths can never drift: a past drift (`JSONEncoder`'s `.iso8601` strategy dropping fractional seconds)
/// floored uploads to whole seconds while the local copy and the server's echo kept milliseconds, so the
/// reconciler saw local as newer and re-uploaded every recipe on every sync. Pairs with
/// `Date.roundedToWireMillis`, which compares instants at this same millisecond resolution. `internal`
/// (not `private`) so the round-trip can be unit-tested.
enum SyncWireDate {
    /// Serializes to the wire format the server expects (millisecond fractional seconds, trailing `Z`).
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Parses a server timestamp, tolerating the format variants the server and GRDB are known to emit:
    /// ISO-8601 with then without fractional seconds, a `T`-separated value lacking a timezone, GRDB's
    /// space-separated local format, and a microsecond-precision variant. Order matters — the canonical
    /// `.SSS'Z'` form is tried first.
    static func date(from string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }

        for format in [
            "yyyy-MM-dd'T'HH:mm:ss",        // no timezone
            "yyyy-MM-dd HH:mm:ss.SSS",      // GRDB default (space-separated)
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", // microseconds
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}

extension Date {
    /// Rounded to whole milliseconds — the resolution of the sync wire format (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`).
    /// The local `Date` (decoded by SQLiteData from `"yyyy-MM-dd HH:mm:ss.SSS"`) and the server `Date`
    /// (decoded by `ISO8601DateFormatter`) can differ by sub-microsecond amounts for the SAME wall-clock
    /// millisecond, so comparing them with `>` / `<` made sync re-upload/re-download everything forever.
    /// Normalizing both sides to whole milliseconds before comparison makes equal instants compare equal.
    var roundedToWireMillis: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate * 1000).rounded() / 1000)
    }
}

// MARK: - Sync Progress

struct SyncProgress {
    var currentStep: String = ""
    var itemsUploaded: Int = 0
    var itemsDownloaded: Int = 0
    var imagesUploaded: Int = 0
    var imagesDownloaded: Int = 0
    var uploadedRecipeIds: Set<String> = []   // Track which recipes were uploaded (local was newer)
    var downloadedRecipeIds: Set<String> = [] // Track which recipes were downloaded (server was newer)
    
    var summary: String {
        "↑ \(itemsUploaded) items, \(imagesUploaded) images | ↓ \(itemsDownloaded) items, \(imagesDownloaded) images"
    }
    
    mutating func reset() {
        currentStep = ""
        itemsUploaded = 0
        itemsDownloaded = 0
        imagesUploaded = 0
        imagesDownloaded = 0
        uploadedRecipeIds = []
        downloadedRecipeIds = []
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case serverNotConfigured
    case credentialsNotConfigured
    case authenticationFailed(String)
    case networkError(String)
    case uploadFailed(String)
    case downloadFailed(String)
    case parseError(String)
    /// The user stopped the sync. Normalized from `CancellationError`/`URLError.cancelled` by
    /// `performFullSync()` so callers can tell "you cancelled" apart from "something went wrong".
    case cancelled
    /// A sync finished within `minimumSyncInterval`, so this one was skipped. Benign: every caller
    /// treats it as "already up to date", never as a failure (and it must not clear auto-sync's
    /// pending-changes state the way a real success does).
    case throttled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sync was cancelled."
        case .throttled:
            return "Sync skipped: already synced a moment ago."
        case .serverNotConfigured:
            return "Server URL is not configured. Please set it in Settings."
        case .credentialsNotConfigured:
            return "Username and password are not configured. Please set them in Settings."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

extension SyncError {
    /// True when `error` means "this sync was cancelled" in any of the forms it can arrive in: a Swift task
    /// cancellation, the `URLError` URLSession raises for the request it aborted, or our own normalized
    /// `.cancelled`. Used to keep a deliberate cancel out of the error paths (no red banner in Settings, no
    /// auto-sync failure count).
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let syncError = error as? SyncError, case .cancelled = syncError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// User-facing message for a non-2xx HTTP response that never surfaces the raw response body, which
    /// could be HTML error page (proxy 502, captive portal, wrong address) that shouldn't be shown as raw text.
    /// If the body is small JSON carrying an `error`/`message`/`detail` field, that text is preferred.
    static func httpMessage(status: Int, body: Data) -> String {
        if let serverMessage = serverJSONMessage(from: body) { return serverMessage }
        // An HTML body (not Salty Server JSON) means something else must have answered: a reverse proxy,
        // captive portal, etc. In particular, NGINX returns HTML 403 page (and actual 403 code) if access
        // list does not allow, so lead with that possibility since that is likely a common Salty Server setup:
        if bodyLooksLikeHTML(body) {
            return "Access to the server was forbidden (HTTP \(status)). A reverse proxy, firewall, portal (sever responded with HTML), or other issue may be blocking access. Verify your network connection, server setup, and try again."
        }
        switch status {
        case 401:
            return "The server rejected your saved username or password (HTTP 401)."
        case 403:
            return "Access to the server was forbidden (HTTP 403). Check firewall or IP restrictions, and verify your username and password."
        case 404:
            return "The server didn't recognize that request (HTTP 404). Check server address."
        case 408, 429:
            return "Error: HTTP \(status). Server may be busy. Try again in a moment."
        case 500...599:
            return "Error: HTTP \(status). Ensure server is functional and try again."
        default:
            return "The server returned an unexpected response (HTTP \(status))."
        }
    }

    /// True when the body looks like an HTML/markup page rather than our JSON API response. Our API always
    /// returns JSON (starts with `{` or `[`); a leading `<` means an HTML/XML page from a proxy/gateway.
    private static func bodyLooksLikeHTML(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let prefix = String(data: data.prefix(512), encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return prefix.hasPrefix("<")
    }

    /// Extracts a human message from a SMALL JSON error body. Returns nil for HTML / large / non-JSON bodies.
    private static func serverJSONMessage(from data: Data) -> String? {
        guard !data.isEmpty, data.count < 4096,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["message", "error", "detail"] {
            if let text = object[key] as? String, !text.isEmpty { return text }
        }
        return nil
    }
}

/// Maps ANY error thrown during sync to a friendly, HTML-free string for display. Covers our own
/// `SyncError` (already friendly), connectivity failures (`URLError`), and unreadable responses
/// (`DecodingError`, e.g. an HTML page where JSON was expected).
func friendlySyncMessage(_ error: Error) -> String {
    // Checked first: a cancelled request is a `URLError` whose default wording ("Couldn't reach the
    // server") would blame the network for something the user chose to do.
    if SyncError.isCancellation(error) {
        return "Sync was cancelled. Anything already transferred was kept — sync again to finish the rest."
    }
    switch error {
    case let urlError as URLError:
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "No internet connection. Connect to a network and try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut, .secureConnectionFailed:
            return "Couldn't reach the server. It may be offline or only reachable on your home network. Check the server address in Settings."
        default:
            return "Couldn't reach the server (\(urlError.localizedDescription))"
        }
    case is DecodingError:
        return "The server returned a response the app couldn't read. Check that the address points to your Salty server."
    case let syncError as SyncError:
        return syncError.errorDescription ?? "Sync failed."
    default:
        return error.localizedDescription
    }
}

// MARK: - Server DTOs (Data Transfer Objects)

/// Matches Spring Boot Recipe model
/// Lightweight entry from GET /api/recipes/sync/manifest: a recipe's id + last-modified timestamp,
/// used to reconcile existence/deletions without downloading full bodies.
struct ServerRecipeManifestEntry: Codable {
    var id: String
    var lastModifiedDate: Date?
    // Image filename + image timestamp let the client reconcile image transfer independently of the body.
    var imageFilename: String?
    var lastModifiedImageDate: Date?
}

struct ServerRecipe: Codable {
    var id: String
    var name: String
    var createdDate: Date?
    var lastModifiedDate: Date?
    var lastPrepared: Date?
    var source: String?
    var sourceDetails: String?
    var introduction: String?
    var difficulty: Int?
    var rating: Int?
    var imageFilename: String?
    var lastModifiedImageDate: Date?
    var isFavorite: Bool?
    var wantToMake: Bool?
    var yield: String?
    var servings: Int?
    var courseId: String?  // Using course.id from server
    var directions: [ServerDirection]?
    var ingredients: [ServerIngredient]?
    var notes: [ServerNote]?
    var variations: [ServerVariation]?
    var preparationTimes: [ServerPreparationTime]?
    var nutrition: ServerNutrition?
    
    // Server sends course as nested object, we need to extract ID
    var course: ServerCourse?
    
    // Category and tag relationships
    var categoryIds: [String]?
    var tagIds: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, createdDate, lastModifiedDate, lastPrepared
        case source, sourceDetails, introduction
        case difficulty, rating, imageFilename, lastModifiedImageDate
        case isFavorite, wantToMake, yield, servings
        case courseId, course
        case directions, ingredients, notes, variations
        case preparationTimes, nutrition
        case categoryIds, tagIds
    }
    
    static func from(_ recipe: Recipe) -> ServerRecipe {
        return ServerRecipe(
            id: recipe.id,
            name: recipe.name,
            createdDate: recipe.createdDate,
            lastModifiedDate: recipe.lastModifiedDate,
            lastPrepared: recipe.lastPrepared,
            source: recipe.source,
            sourceDetails: recipe.sourceDetails,
            introduction: recipe.introduction,
            difficulty: recipe.difficulty.rawValue,
            rating: recipe.rating.rawValue,
            imageFilename: recipe.imageFilename,
            lastModifiedImageDate: recipe.lastModifiedImageDate,
            isFavorite: recipe.isFavorite,
            wantToMake: recipe.wantToMake,
            yield: recipe.yield,
            servings: recipe.servings,
            courseId: recipe.courseId,
            directions: recipe.directions.map { ServerDirection.from($0) },
            ingredients: recipe.ingredients.map { ServerIngredient.from($0) },
            notes: recipe.notes.map { ServerNote.from($0) },
            variations: recipe.variations.map { ServerVariation.from($0) },
            preparationTimes: recipe.preparationTimes.map { ServerPreparationTime.from($0) },
            nutrition: recipe.nutrition.map { ServerNutrition.from($0) }
        )
    }
    
    func toLocalRecipe() -> Recipe {
        return Recipe(
            id: id,
            name: name,
            createdDate: createdDate ?? Date(),
            lastModifiedDate: lastModifiedDate ?? Date(),
            lastPrepared: lastPrepared,
            source: source ?? "",
            sourceDetails: sourceDetails ?? "",
            introduction: introduction ?? "",
            difficulty: Difficulty(rawValue: difficulty ?? 0) ?? .notSet,
            rating: Rating(rawValue: rating ?? 0) ?? .notSet,
            imageFilename: imageFilename,
            imageThumbnailData: nil, // Will be set when image is downloaded
            lastModifiedImageDate: lastModifiedImageDate,
            isFavorite: isFavorite ?? false,
            wantToMake: wantToMake ?? false,
            yield: yield ?? "",
            servings: servings,
            courseId: course?.id ?? courseId,
            directions: directions?.map { $0.toLocal() } ?? [],
            ingredients: ingredients?.map { $0.toLocal() } ?? [],
            notes: notes?.map { $0.toLocal() } ?? [],
            variations: variations?.map { $0.toLocal() } ?? [],
            preparationTimes: preparationTimes?.map { $0.toLocal() } ?? [],
            nutrition: nutrition?.toLocal()
        )
    }
}

struct ServerDirection: Codable {
    var id: String
    var isHeading: Bool?
    var text: String
    
    static func from(_ direction: Direction) -> ServerDirection {
        ServerDirection(id: direction.id, isHeading: direction.isHeading, text: direction.text)
    }
    
    func toLocal() -> Direction {
        Direction(id: id, isHeading: isHeading, text: text)
    }
}

struct ServerIngredient: Codable {
    var id: String
    var isHeading: Bool?
    var isMain: Bool?
    var text: String
    
    static func from(_ ingredient: Ingredient) -> ServerIngredient {
        ServerIngredient(id: ingredient.id, isHeading: ingredient.isHeading, isMain: ingredient.isMain, text: ingredient.text)
    }
    
    func toLocal() -> Ingredient {
        Ingredient(id: id, isHeading: isHeading ?? false, isMain: isMain ?? false, text: text)
    }
}

struct ServerNote: Codable {
    var id: String
    var title: String?
    var content: String?
    var text: String?  // Server might use 'text' instead of 'content'
    
    static func from(_ note: Note) -> ServerNote {
        ServerNote(id: note.id, title: note.title, content: note.content, text: nil)
    }
    
    func toLocal() -> Note {
        Note(id: id, title: title ?? "", content: content ?? text ?? "")
    }
}

struct ServerVariation: Codable {
    var id: String
    var variationName: String?
    var text: String
    
    static func from(_ variation: Variation) -> ServerVariation {
        ServerVariation(id: variation.id, variationName: variation.variationName, text: variation.text)
    }
    
    func toLocal() -> Variation {
        Variation(id: id, variationName: variationName ?? "", text: text)
    }
}

struct ServerPreparationTime: Codable {
    var id: String
    var type: String
    var timeString: String
    
    static func from(_ prepTime: PreparationTime) -> ServerPreparationTime {
        ServerPreparationTime(id: prepTime.id, type: prepTime.type, timeString: prepTime.timeString)
    }
    
    func toLocal() -> PreparationTime {
        PreparationTime(id: id, type: type, timeString: timeString)
    }
}

struct ServerNutrition: Codable {
    var id: String?
    var servingSize: String?
    var calories: Double?
    var protein: Double?
    var carbohydrates: Double?
    var fat: Double?
    var saturatedFat: Double?
    var transFat: Double?
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?
    var cholesterol: Double?
    var addedSugar: Double?
    var vitaminD: Double?
    var calcium: Double?
    var iron: Double?
    var potassium: Double?
    var vitaminA: Double?
    var vitaminC: Double?
    
    static func from(_ nutrition: NutritionInformation) -> ServerNutrition {
        ServerNutrition(
            id: nutrition.id,
            servingSize: nutrition.servingSize,
            calories: nutrition.calories,
            protein: nutrition.protein,
            carbohydrates: nutrition.carbohydrates,
            fat: nutrition.fat,
            saturatedFat: nutrition.saturatedFat,
            transFat: nutrition.transFat,
            fiber: nutrition.fiber,
            sugar: nutrition.sugar,
            sodium: nutrition.sodium,
            cholesterol: nutrition.cholesterol,
            addedSugar: nutrition.addedSugar,
            vitaminD: nutrition.vitaminD,
            calcium: nutrition.calcium,
            iron: nutrition.iron,
            potassium: nutrition.potassium,
            vitaminA: nutrition.vitaminA,
            vitaminC: nutrition.vitaminC
        )
    }
    
    func toLocal() -> NutritionInformation {
        NutritionInformation(
            id: id ?? UUIDV7().uuidString,
            servingSize: servingSize,
            calories: calories,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat,
            saturatedFat: saturatedFat,
            transFat: transFat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            cholesterol: cholesterol,
            addedSugar: addedSugar,
            vitaminD: vitaminD,
            calcium: calcium,
            iron: iron,
            potassium: potassium,
            vitaminA: vitaminA,
            vitaminC: vitaminC
        )
    }
}

struct ServerCourse: Codable {
    var id: String
    var name: String?
    var lastModifiedDate: Date?
}

struct ServerCategory: Codable {
    var id: String
    var name: String?
    var lastModifiedDate: Date?
}

struct ServerTag: Codable {
    var id: String
    var name: String?
    var lastModifiedDate: Date?
}

/// Wire shape for a shopping list. Mirrors SaltyKMP's `ServerShoppingList` and the server's
/// `shopping_list` table. Everything past `id` is optional so a client predating a field still
/// round-trips — there is no protocol version field to negotiate with.
struct ServerShoppingList: Codable {
    var id: String
    var name: String?
    var isFreeform: Bool?
    var contentsForList: [ShoppingListListContents]?
    var contentsForFreeform: String?
    var lastModifiedDate: Date?
    /// Server-owned optimistic-concurrency counter: present on every GET/save response, bumped on
    /// every accepted write. Nil only from clients or servers that predate revisions.
    var revision: Int64?
    /// Client → server on upload: the `revision` this edit is based on. The server rejects the write
    /// with 409 (+ its current row) when this no longer matches — that mismatch IS conflict
    /// detection. Legacy clients omit it and get timestamp-guarded last-writer-wins instead.
    /// Encoding stays synthesized (`encodeIfPresent`), so nil keeps both fields off the wire.
    var baseRevision: Int64?
}

/// Decodes a value, yielding nil instead of throwing. Wrapping array *elements* in this is what makes
/// an array decode item-by-item: decoding the element type directly and catching would leave the
/// container's index unadvanced, so the loop couldn't make progress.
private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension ServerShoppingList {
    private enum CodingKeys: String, CodingKey {
        case id, name, isFreeform, contentsForList, contentsForFreeform, lastModifiedDate
        case revision, baseRevision
    }

    /// Hand-written purely so `contentsForList` decodes item-by-item: one malformed item would
    /// otherwise throw out of `fetchListFromServer` and abort the ENTIRE sync — recipes included —
    /// on every attempt, with no way for the user to clear it.
    ///
    /// The leniency deliberately stops at the item level, in two directions:
    ///
    /// - The array of *lists* stays strict (this is per-list decoding). Silently dropping an
    ///   undecodable list would read as "the server no longer has it", and the reconciler infers
    ///   deletions from absence — so it would delete that list locally, or push a deletion for it.
    /// - A `contentsForList` that isn't an array at all still throws. Coercing it to empty would
    ///   quietly blank a list, and the next upload would make that permanent.
    ///
    /// Both of those are cases where failing loudly loses less than recovering quietly.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let listId = try container.decode(String.self, forKey: .id)
        id = listId
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isFreeform = try container.decodeIfPresent(Bool.self, forKey: .isFreeform)
        contentsForFreeform = try container.decodeIfPresent(String.self, forKey: .contentsForFreeform)
        lastModifiedDate = try container.decodeIfPresent(Date.self, forKey: .lastModifiedDate)
        revision = try container.decodeIfPresent(Int64.self, forKey: .revision)
        baseRevision = try container.decodeIfPresent(Int64.self, forKey: .baseRevision)

        if let wrapped = try container.decodeIfPresent([FailableDecodable<ShoppingListListContents>].self, forKey: .contentsForList) {
            let items = wrapped.compactMap(\.value)
            if items.count != wrapped.count {
                let skipped = wrapped.count - items.count
                Logger(subsystem: "Salty", category: "Sync").error(
                    "Shopping list \(listId): skipped \(skipped) unreadable item(s) from the server payload"
                )
            }
            contentsForList = items
        } else {
            contentsForList = nil
        }
    }
}

// Conversions live in an extension so the memberwise init survives — a hand-written `init` in the
// body would suppress it, and constructing a sparse payload directly is exactly how an older peer's
// response is represented.
extension ServerShoppingList {
    init(list: ShoppingList) {
        self.id = list.id
        self.name = list.name
        self.isFreeform = list.isFreeform
        self.contentsForList = list.contentsForList
        self.contentsForFreeform = list.contentsForFreeform
        self.lastModifiedDate = list.lastModifiedDate
    }

    /// The local row this payload represents. `lastModifiedDate` falls back to "now" rather than
    /// `distantPast`: a nil would compare as older than the sync watermark forever, so the list would
    /// be re-deleted on the next sync instead of kept (same hazard `coalesceNullShoppingListColumns`
    /// guards against locally).
    var asShoppingList: ShoppingList {
        ShoppingList(
            id: id,
            name: name ?? "",
            isFreeform: isFreeform ?? false,
            contentsForFreeform: contentsForFreeform,
            contentsForList: contentsForList ?? [],
            lastModifiedDate: lastModifiedDate ?? Date()
        )
    }
}
