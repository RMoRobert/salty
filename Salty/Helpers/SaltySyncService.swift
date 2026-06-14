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
class SaltySyncService: ObservableObject {
    static let shared = SaltySyncService()
    
    private let logger = Logger(subsystem: "Salty", category: "Sync")
    
    @Dependency(\.defaultDatabase) private var database
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var lastSyncError: String?
    @Published var syncProgress: SyncProgress = SyncProgress()
    
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
    
    private init() {}
    
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.authenticationFailed("Invalid response from server")
        }
        
        if httpResponse.statusCode == 401 {
            throw SyncError.authenticationFailed("Invalid username or password")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SyncError.authenticationFailed("Login failed (HTTP \(httpResponse.statusCode)): \(body)")
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
    
    /// Performs a full bidirectional sync with the server
    func syncNow() async throws {
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
        
        isSyncing = true
        lastSyncError = nil
        syncProgress = SyncProgress()
        
        defer {
            isSyncing = false
        }
        
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
            
            // Step 7: Mark sync complete on server
            logger.info("Step 7: Completing sync...")
            syncProgress.currentStep = "Completing sync..."
            try await completeSyncOnServer()
            logger.info("Sync marked complete on server")
            
            lastSyncDate = Date()
            syncProgress.currentStep = "Sync complete!"
            logger.info("Sync completed successfully")
            
        } catch {
            lastSyncError = error.localizedDescription
            logger.error("Sync failed at step '\(self.syncProgress.currentStep)': \(error)")
            throw error
        }
    }
    
    /// Guards bulk LOCAL deletions against a truncated/empty server response. The deletion
    /// heuristic ("present locally, absent from server, unchanged since last sync ⇒ deleted on
    /// the server") is dangerous if the server ever returns an empty list due to a transient
    /// failure rather than real deletions — it would wipe local data. So if the server returned
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
                let serverDate = serverCourse.lastModifiedDate ?? Date.distantPast
                let localDate = localCourse.lastModifiedDate ?? Date.distantPast
                
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
                    let localDate = localCourse.lastModifiedDate ?? Date.distantPast
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
                    let serverDate = serverCourse.lastModifiedDate ?? Date.distantPast
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
                let serverDate = serverCategory.lastModifiedDate ?? Date.distantPast
                let localDate = localCategory.lastModifiedDate ?? Date.distantPast
                
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
                    let localDate = localCategory.lastModifiedDate ?? Date.distantPast
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
                    let serverDate = serverCategory.lastModifiedDate ?? Date.distantPast
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
                let serverDate = serverTag.lastModifiedDate ?? Date.distantPast
                let localDate = localTag.lastModifiedDate ?? Date.distantPast
                
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
                    let localDate = localTag.lastModifiedDate ?? Date.distantPast
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
                    let serverDate = serverTag.lastModifiedDate ?? Date.distantPast
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
    
    /// Mark sync as complete on server
    private func completeSyncOnServer() async throws {
        guard let url = URL(string: "\(serverUrl)/api/recipes/sync/device/\(deviceId)/complete") else {
            throw SyncError.uploadFailed("Invalid server URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            logger.warning("Failed to mark sync complete on server")
            return
        }
    }
    
    /// Sync recipes with deletion detection based on device's last sync time
    private func syncRecipesWithDeletions(deviceInfo: DeviceInfo) async throws {
        let serverRecipes = try await fetchListFromServer(ServerRecipe.self, endpoint: "/api/recipes")
        let localRecipes = try await database.read { db in
            try Recipe.fetchAll(db)
        }
        
        let serverRecipesById = Dictionary(serverRecipes.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localRecipesById = Dictionary(localRecipes.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localRecipeIds = Set(localRecipes.map { $0.id })
        
        var recipesToDeleteOnServer: [String] = []
        var recipesToDeleteLocally: [String] = []
        
        // Process each local recipe
        for localRecipe in localRecipes {
            if let serverRecipe = serverRecipesById[localRecipe.id] {
                // Recipe exists on both sides - compare timestamps
                let serverDate = serverRecipe.lastModifiedDate ?? Date.distantPast
                let localDate = localRecipe.lastModifiedDate
                
                if localDate > serverDate {
                    // Local is newer - upload to server
                    try await uploadRecipe(localRecipe)
                    syncProgress.itemsUploaded += 1
                    syncProgress.uploadedRecipeIds.insert(localRecipe.id)
                } else if serverDate > localDate {
                    // Server is newer - download from server
                    try await downloadRecipe(serverRecipe)
                    syncProgress.itemsDownloaded += 1
                    syncProgress.downloadedRecipeIds.insert(serverRecipe.id)
                }
            } else {
                // Recipe only exists locally
                if deviceInfo.isFirstSync {
                    // First sync - upload everything
                    try await uploadRecipe(localRecipe)
                    syncProgress.itemsUploaded += 1
                    syncProgress.uploadedRecipeIds.insert(localRecipe.id)
                } else if let lastSync = deviceInfo.lastSyncDate {
                    // Check if recipe is newer than last sync
                    if localRecipe.lastModifiedDate > lastSync {
                        // New recipe created after last sync - upload
                        try await uploadRecipe(localRecipe)
                        syncProgress.itemsUploaded += 1
                        syncProgress.uploadedRecipeIds.insert(localRecipe.id)
                    } else {
                        // Recipe existed before last sync but not on server - was deleted on server
                        recipesToDeleteLocally.append(localRecipe.id)
                    }
                } else {
                    // No last sync date, treat as new
                    try await uploadRecipe(localRecipe)
                    syncProgress.itemsUploaded += 1
                    syncProgress.uploadedRecipeIds.insert(localRecipe.id)
                }
            }
        }
        
        // Process recipes only on server
        logger.info("Processing \(serverRecipes.count) server recipes, \(localRecipeIds.count) local recipes")
        
        for serverRecipe in serverRecipes {
            if !localRecipeIds.contains(serverRecipe.id) {
                logger.debug("Recipe '\(serverRecipe.name)' (\(serverRecipe.id)) is on server but not locally")
                
                if deviceInfo.isFirstSync {
                    // First sync - download everything from server
                    logger.debug("  -> First sync: downloading")
                    try await downloadRecipe(serverRecipe)
                    syncProgress.itemsDownloaded += 1
                    syncProgress.downloadedRecipeIds.insert(serverRecipe.id)
                } else if let lastSync = deviceInfo.lastSyncDate {
                    let serverDate = serverRecipe.lastModifiedDate ?? Date.distantPast
                    logger.debug("  -> Comparing: serverDate=\(serverDate), lastSync=\(lastSync), serverDate > lastSync = \(serverDate > lastSync)")
                    
                    if serverDate > lastSync {
                        // Recipe created/modified on server after last sync - download
                        logger.debug("  -> Server recipe is newer than last sync: downloading")
                        try await downloadRecipe(serverRecipe)
                        syncProgress.itemsDownloaded += 1
                        syncProgress.downloadedRecipeIds.insert(serverRecipe.id)
                    } else {
                        // Recipe existed before last sync but not locally - was deleted locally
                        logger.info("  -> Recipe was deleted locally (serverDate \(serverDate) <= lastSync \(lastSync)): will delete from server")
                        recipesToDeleteOnServer.append(serverRecipe.id)
                    }
                } else {
                    // No last sync date, download
                    logger.debug("  -> No lastSyncDate available: downloading")
                    try await downloadRecipe(serverRecipe)
                    syncProgress.itemsDownloaded += 1
                    syncProgress.downloadedRecipeIds.insert(serverRecipe.id)
                }
            }
        }
        
        logger.info("Sync decision summary: \(recipesToDeleteOnServer.count) to delete on server, \(recipesToDeleteLocally.count) to delete locally")
        
        // Delete recipes locally that were deleted on server
        // (guarded against empty-response wipes; DB deletes batched in one transaction)
        let recipeIdsToDeleteLocally = recipesToDeleteLocally
        if serverResponseAllowsLocalDeletions(serverItemCount: serverRecipes.count, pendingLocalDeletions: recipeIdsToDeleteLocally.count, entity: "recipe") {
            for recipeId in recipeIdsToDeleteLocally {
                logger.info("Deleting recipe \(recipeId) locally (was deleted on another device)")
                if let recipe = localRecipesById[recipeId], let filename = recipe.imageFilename {
                    RecipeImageManager.shared.deleteImage(filename: filename)
                }
            }
            try await database.write { db in
                for recipeId in recipeIdsToDeleteLocally {
                    _ = try Recipe.deleteOne(db, key: recipeId)
                }
            }
            syncProgress.itemsDownloaded += recipeIdsToDeleteLocally.count // Count as sync actions
        }
        
        // Delete recipes on server that were deleted locally
        if !recipesToDeleteOnServer.isEmpty {
            logger.info("Deleting \(recipesToDeleteOnServer.count) recipe(s) on server (were deleted locally)")
            try await deleteRecipesOnServer(recipeIds: recipesToDeleteOnServer)
        }
        
        if !recipesToDeleteLocally.isEmpty || !recipesToDeleteOnServer.isEmpty {
            logger.info("Deletion sync: \(recipesToDeleteLocally.count) deleted locally, \(recipesToDeleteOnServer.count) deleted on server")
        }
    }
    
    /// Delete recipes on the server
    private func deleteRecipesOnServer(recipeIds: [String]) async throws {
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            logger.warning("Failed to delete recipes on server")
            return
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let deleted = json["deleted"] as? Int {
            logger.info("Server deleted \(deleted) recipe(s)")
        }
    }
    
    /// Parse server date string to Date
    private func parseServerDate(_ dateStr: String) -> Date? {
        let formatters: [DateFormatter] = {
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ss.SSS"
            ]
            return formats.map { format in
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.timeZone = TimeZone(identifier: "UTC")
                return formatter
            }
        }()
        
        for formatter in formatters {
            if let date = formatter.date(from: dateStr) {
                return date
            }
        }
        return nil
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
            // Check if recipe already exists
            let exists = try Recipe.where { $0.id.eq(recipe.id) }.fetchOne(db) != nil
            
            if exists {
                try Recipe.update(recipe).execute(db)
                logger.debug("Updated existing recipe: \(recipe.name)")
            } else {
                try Recipe.insert { recipe }.execute(db)
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
    
    private func syncImages() async throws {
        let localRecipes = try await database.read { db in
            try Recipe.fetchAll(db)
        }
        
        var imageErrors: [String] = []
        var imagesAlreadyOnServer = 0
        var totalImagesToSync = 0
        var recipesWithImageFilename = 0
        var recipesWithLoadableImage = 0
        var recipesWithoutImage = 0
        
        logger.info("Image sync starting for \(localRecipes.count) recipes")
        
        for recipe in localRecipes {
            // Upload local images that might not be on server
            if let imageFilename = recipe.imageFilename {
                recipesWithImageFilename += 1
                
                if let imageData = RecipeImageManager.shared.loadImage(filename: imageFilename) {
                    recipesWithLoadableImage += 1
                    totalImagesToSync += 1
                    logger.debug("Recipe '\(recipe.name)': has image '\(imageFilename)' (\(imageData.count) bytes)")
                    
                    do {
                        // URL-encode the filename for the check
                        guard let encodedFilename = imageFilename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                            logger.warning("Could not URL-encode filename: \(imageFilename)")
                            continue
                        }
                        
                        // Check if image exists on server
                        let imageExists = try await checkExists(endpoint: "/api/recipes/images/\(encodedFilename)")
                        
                        // Upload if: image doesn't exist on server, OR recipe was uploaded (local is newer)
                        let recipeWasUploaded = syncProgress.uploadedRecipeIds.contains(recipe.id)
                        
                        if !imageExists {
                            logger.debug("Uploading image for recipe: \(recipe.name) (not on server)")
                            try await uploadImage(imageData, for: recipe.id)
                            syncProgress.imagesUploaded += 1
                            logger.info("Uploaded image for recipe: \(recipe.name)")
                        } else if recipeWasUploaded {
                            // Recipe was uploaded because local was newer - also update image
                            logger.debug("Uploading image for recipe: \(recipe.name) (recipe was updated)")
                            try await uploadImage(imageData, for: recipe.id)
                            syncProgress.imagesUploaded += 1
                            logger.info("Updated image for recipe: \(recipe.name)")
                        } else {
                            imagesAlreadyOnServer += 1
                            logger.debug("Image already on server for recipe: \(recipe.name)")
                        }
                    } catch {
                        // Log and continue instead of failing entire sync
                        logger.error("Failed to upload image for recipe \(recipe.name): \(error.localizedDescription)")
                        imageErrors.append(recipe.name)
                    }
                } else {
                    logger.warning("Recipe '\(recipe.name)': has imageFilename '\(imageFilename)' but file not found locally")
                }
            } else {
                recipesWithoutImage += 1
            }
            
            // Download server images if:
            // 1. We don't have the file locally (no filename or file missing)
            // 2. The recipe was downloaded (server was newer) - server image may be different
            let recipeWasDownloaded = syncProgress.downloadedRecipeIds.contains(recipe.id)
            let needsDownload: Bool
            let downloadReason: String
            
            if recipeWasDownloaded {
                // Recipe was downloaded (server was newer) - always get server's image
                needsDownload = true
                downloadReason = "recipe was updated from server"
            } else if let imageFilename = recipe.imageFilename {
                // Has filename but file doesn't exist locally - need to download
                needsDownload = RecipeImageManager.shared.loadImage(filename: imageFilename) == nil
                downloadReason = "file missing locally"
            } else {
                // No filename at all - check if server has one
                needsDownload = true
                downloadReason = "no local image"
            }
            
            if needsDownload {
                do {
                    // Check if server has an image for this recipe
                    if let serverImageFilename = try await fetchRecipeImageFilename(recipeId: recipe.id) {
                        logger.debug("Server has image '\(serverImageFilename)' for recipe '\(recipe.name)' (\(downloadReason)), downloading...")
                        try await downloadImage(filename: serverImageFilename, for: recipe.id)
                        syncProgress.imagesDownloaded += 1
                        logger.info("Downloaded image for recipe: \(recipe.name) (\(downloadReason))")
                    }
                } catch {
                    logger.error("Failed to download image for recipe \(recipe.name): \(error.localizedDescription)")
                    imageErrors.append(recipe.name)
                }
            }
        }
        
        // Log detailed summary
        logger.info("Image sync summary: \(recipesWithImageFilename) have imageFilename, \(recipesWithLoadableImage) loadable, \(recipesWithoutImage) without image")
        logger.info("Image sync: \(self.syncProgress.imagesUploaded) uploaded, \(imagesAlreadyOnServer) already existed, \(imageErrors.count) failed, \(self.syncProgress.imagesDownloaded) downloaded")
        
        // Only throw if we have errors and made no progress at all
        // (i.e., nothing uploaded, nothing downloaded, and nothing was already synced)
        if !imageErrors.isEmpty {
            if syncProgress.imagesUploaded == 0 && syncProgress.imagesDownloaded == 0 && imagesAlreadyOnServer == 0 {
                throw SyncError.uploadFailed("Image sync failed for: \(imageErrors.joined(separator: ", "))")
            } else {
                // Some succeeded, just log a warning
                logger.warning("Some images failed to sync: \(imageErrors.joined(separator: ", "))")
            }
        }
    }
    
    private func uploadImage(_ imageData: Data, for recipeId: String) async throws {
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
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
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
    
    private func downloadImage(filename: String, for recipeId: String) async throws {
        let url = URL(string: "\(serverUrl)/api/recipes/images/\(filename)")!
        logger.debug("Downloading image from: \(url)")
        
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.warning("No HTTP response for image download: \(filename)")
            return
        }
        
        guard httpResponse.statusCode == 200 else {
            logger.warning("Image download failed for '\(filename)': HTTP \(httpResponse.statusCode)")
            return
        }
        
        logger.debug("Downloaded image '\(filename)': \(data.count) bytes")
        
        // Save image locally and update recipe
        if let result = RecipeImageManager.shared.saveImage(data, for: recipeId) {
            logger.debug("Saved image as '\(result.filename)' with \(result.thumbnailData.count) byte thumbnail")
            try await database.write { db in
                try db.execute(sql: """
                    UPDATE recipe 
                    SET imageFilename = ?, imageThumbnailData = ?
                    WHERE id = ?
                    """,
                    arguments: [result.filename, result.thumbnailData, recipeId]
                )
            }
            logger.info("Updated recipe \(recipeId) with downloaded image")
        } else {
            logger.error("Failed to save downloaded image for recipe \(recipeId)")
        }
    }
    
    private func fetchRecipeImageFilename(recipeId: String) async throws -> String? {
        let serverRecipe = try? await fetchFromServer(ServerRecipe.self, endpoint: "/api/recipes/\(recipeId)")
        return serverRecipe?.imageFilename
    }
    
    // MARK: - Network Helpers
    
    private func fetchFromServer<T: Decodable>(_ type: T.Type, endpoint: String) async throws -> T {
        try await fetchFromServerWithTotalCount(type, endpoint: endpoint).value
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

    /// Fetches and decodes `T`, also returning the server's `X-Total-Count` header value if present.
    private func fetchFromServerWithTotalCount<T: Decodable>(_ type: T.Type, endpoint: String) async throws -> (value: T, totalCount: Int?) {
        let url = URL(string: "\(serverUrl)\(endpoint)")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            logger.error("HTTP \(statusCode) from \(endpoint): \(responseBody.prefix(500))")
            throw SyncError.networkError("Failed to fetch from \(endpoint) (HTTP \(statusCode))")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 with fractional seconds first (e.g., 2025-10-17T21:43:10.000Z)
            // This should match what Salty Server uses by default with its database
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            // But if not, try some likely alternatives...
            // Try without fractional seconds (e.g., 2025-10-17T21:43:10Z)
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            // Try without timezone (e.g., 2025-10-17T21:43:10)
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            // Fallback: Try GRDB default format (e.g., 2025-10-17 21:43:10.000)
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
        
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
    
    private func postToServer<T: Encodable>(_ object: T, endpoint: String) async throws {
        let url = URL(string: "\(serverUrl)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(object)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "No body"
            throw SyncError.uploadFailed("POST to \(endpoint) failed (HTTP \(statusCode)): \(body.prefix(200))")
        }
    }
    
    private func putToServer<T: Encodable>(_ object: T, endpoint: String) async throws {
        let url = URL(string: "\(serverUrl)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(object)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "No body"
            throw SyncError.uploadFailed("PUT to \(endpoint) failed (HTTP \(statusCode)): \(body.prefix(200))")
        }
    }
    
    private func deleteOnServer(endpoint: String) async throws {
        guard let url = URL(string: "\(serverUrl)\(endpoint)") else {
            throw SyncError.uploadFailed("Invalid URL for DELETE: \(endpoint)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
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
            let (_, response) = try await URLSession.shared.data(for: request)
            
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
    
    var errorDescription: String? {
        switch self {
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

// MARK: - Server DTOs (Data Transfer Objects)

/// Matches Spring Boot Recipe model
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
        case difficulty, rating, imageFilename
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
