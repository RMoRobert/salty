//
//  SyncProgressText.swift
//  Salty
//
//  The Apple app's wording for sync progress. SaltyCore reports a `SyncProgress.Step` and counts; how
//  they read is up to each client. English for now; plurals go through Foundation's automatic grammar
//  agreement (`inflect: true`), so localising later is a string catalog, not a code change.
//

import Foundation
import SaltyCore

extension SyncProgress.Step {
    /// What Settings shows while a sync is at this step.
    var label: String {
        switch self {
        case .idle: ""
        case .authenticating: "Authenticating…"
        case .registeringDevice: "Registering device…"
        case .syncingCourses: "Syncing courses…"
        case .syncingCategories: "Syncing categories…"
        case .syncingTags: "Syncing tags…"
        case .syncingShoppingLists: "Syncing shopping lists…"
        case .syncingRecipes: "Syncing recipes…"
        case .syncingImages: "Syncing images…"
        case .tidyingLibrary: "Tidying categories, courses, and tags…"
        case .completing: "Completing sync…"
        case .complete: "Sync complete!"
        case .cancelling: "Cancelling…"
        case .cancelled: "Sync cancelled"
        case .downloadingFromServer: "Downloading from server…"
        case .replacingLocalData: "Replacing local data…"
        case .downloadingImages: "Downloading images…"
        case .fullResyncComplete: "Full re-sync complete!"
        case .inspectingServer: "Inspecting server…"
        case .uploadingToServer: "Uploading to server…"
        case .uploadingRecipes: "Uploading recipes…"
        case .removingStaleServerData: "Removing stale server data…"
        case .uploadingImages: "Uploading images…"
        }
    }
}

extension SyncProgress {
    /// One line of what moved, e.g. "↑ 1 item, 2 images | ↓ 0 items, 0 images", plus failed photos.
    var countsSummary: String {
        var line = String(inflected: "↑ ^[\(itemsUploaded) item](inflect: true), ^[\(imagesUploaded) image](inflect: true) | ↓ ^[\(itemsDownloaded) item](inflect: true), ^[\(imagesDownloaded) image](inflect: true)")
        if imagesFailed > 0 {
            line += String(inflected: " | ^[\(imagesFailed) image](inflect: true) failed")
        }
        return line
    }
}
