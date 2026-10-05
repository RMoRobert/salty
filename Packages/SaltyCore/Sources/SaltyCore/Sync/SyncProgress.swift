//
//  SyncProgress.swift
//  SaltyCore
//

import Foundation

/// What a sync in progress is doing, and what it has moved so far.
///
/// The core reports values only; each client words them (the Apple app in `SyncProgressText.swift`,
/// the C# app in `SyncText.cs`).
public struct SyncProgress: Sendable, Equatable {
    /// Where a sync, or a force re-sync in either direction, has got to. The raw values are stable
    /// identifiers for other clients to key their own wording on; they are not for display.
    public enum Step: String, Sendable, Equatable, CaseIterable, Codable {
        /// Nothing has started yet.
        case idle
        /// Checking this device's credentials with the server.
        case authenticating
        /// Telling the server which device is syncing.
        case registeringDevice
        /// Reconciling courses.
        case syncingCourses
        /// Reconciling categories.
        case syncingCategories
        /// Reconciling tags.
        case syncingTags
        /// Reconciling shopping lists.
        case syncingShoppingLists
        /// Reconciling recipe bodies.
        case syncingRecipes
        /// Moving recipe photos.
        case syncingImages
        /// Merging duplicate courses, categories and tags.
        case tidyingLibrary
        /// Recording the finished sync on the server.
        case completing
        /// An ordinary sync finished.
        case complete
        /// The user asked to stop; waiting for the current request.
        case cancelling
        /// The sync stopped at the user's request.
        case cancelled
        /// Force pull: fetching everything from the server.
        case downloadingFromServer
        /// Force pull: replacing the local library.
        case replacingLocalData
        /// Force pull: fetching photos.
        case downloadingImages
        /// A force re-sync, in either direction, finished.
        case fullResyncComplete
        /// Force push: reading what the server holds.
        case inspectingServer
        /// Force push: sending courses, categories, tags and lists.
        case uploadingToServer
        /// Force push: sending recipes.
        case uploadingRecipes
        /// Force push: deleting what this device no longer has.
        case removingStaleServerData
        /// Force push: sending photos.
        case uploadingImages
    }

    public var step: Step = .idle
    public var itemsUploaded: Int = 0
    public var itemsDownloaded: Int = 0
    public var imagesUploaded: Int = 0
    public var imagesDownloaded: Int = 0
    /// Photos that could not be moved in either direction. A sync with these still completes (the
    /// recipes themselves synced), so the count is the only way a user learns a photo is missing.
    public var imagesFailed: Int = 0
    public var uploadedRecipeIds: Set<String> = []   // Track which recipes were uploaded (local was newer)
    public var downloadedRecipeIds: Set<String> = [] // Track which recipes were downloaded (server was newer)

    public init() {}

    public mutating func reset() {
        self = SyncProgress()
    }
}
