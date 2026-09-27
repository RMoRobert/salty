//
//  SyncProgress.swift
//  SaltyCore
//

import Foundation

/// What a sync in progress is doing, and what it has moved so far.
public struct SyncProgress: Sendable, Equatable {
    public var currentStep: String = ""
    public var itemsUploaded: Int = 0
    public var itemsDownloaded: Int = 0
    public var imagesUploaded: Int = 0
    public var imagesDownloaded: Int = 0
    public var uploadedRecipeIds: Set<String> = []   // Track which recipes were uploaded (local was newer)
    public var downloadedRecipeIds: Set<String> = [] // Track which recipes were downloaded (server was newer)

    public init() {}

    public var summary: String {
        "↑ \(itemsUploaded) items, \(imagesUploaded) images | ↓ \(itemsDownloaded) items, \(imagesDownloaded) images"
    }

    public mutating func reset() {
        currentStep = ""
        itemsUploaded = 0
        itemsDownloaded = 0
        imagesUploaded = 0
        imagesDownloaded = 0
        uploadedRecipeIds = []
        downloadedRecipeIds = []
    }
}
