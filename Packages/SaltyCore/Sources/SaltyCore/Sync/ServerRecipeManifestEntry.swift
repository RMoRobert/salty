//
//  ServerRecipeManifestEntry.swift
//  SaltyCore
//
//  The lightweight manifest row from GET /api/recipes/sync/manifest.
//

import Foundation

/// Matches Spring Boot Recipe model
/// Lightweight entry from GET /api/recipes/sync/manifest: a recipe's id + last-modified timestamp,
/// used to reconcile existence/deletions without downloading full bodies.
public struct ServerRecipeManifestEntry: Codable, Sendable {
    public var id: String
    public var lastModifiedDate: Date?
    // Image filename + image timestamp let the client reconcile image transfer independently of the body.
    public var imageFilename: String?
    public var lastModifiedImageDate: Date?
    // Likewise the "last made on" value + its stamp, so the prepared-date pass settles a recipe straight
    // from the manifest instead of fetching bodies to compare one field.
    public var lastPrepared: Date?
    public var lastModifiedPreparedDate: Date?
}
