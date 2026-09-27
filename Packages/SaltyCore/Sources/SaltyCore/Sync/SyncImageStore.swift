//
//  SyncImageStore.swift
//  SaltyCore
//
//  The recipe image files ServerSyncEngine reads and writes, behind a protocol.
//

import Foundation

/// The library's image files, as the sync engine needs them.
///
/// Per-platform because the images folder's location depends on how the app reaches the library (a
/// security-scoped bookmark on Apple platforms), and saving an image also renders its list thumbnail,
/// which needs an image decoder. The Apple app implements this with `RecipeImageManager`.
///
/// Every method is called with names that came from the sync server, so implementations must refuse
/// anything `LibraryFilenames.isSafeComponent` rejects before touching the filesystem.
public protocol SyncImageStore: Sendable {
    /// The stored bytes, or nil when the file is missing or unreadable.
    func loadImage(filename: String) -> Data?

    /// Writes downloaded bytes as this recipe's image and returns the stored filename with the list
    /// thumbnail to put in the recipe row, or nil if it couldn't be saved.
    ///
    /// Must not delete anything: an older file under another extension stays until
    /// `deleteImages(for:except:)`, which the engine calls only after the row pointing at the new file
    /// has been committed.
    func saveImage(_ imageData: Data, for recipeId: String) -> (filename: String, thumbnailData: Data)?

    func deleteImage(filename: String)

    /// Deletes the recipe's image files (any `<recipeId>.<ext>`) except `keep`.
    func deleteImages(for recipeId: String, except keep: String?)
}
