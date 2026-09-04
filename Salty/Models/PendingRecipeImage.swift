//
//  PendingRecipeImage.swift
//  Salty
//
//  An image change the user has made in an editor but not yet saved.
//
//  The editors used to write straight to disk the moment an image was picked, pasted, dropped, or
//  deleted, which meant Cancel could not undo it: the recipe struct rolled back, but the file under
//  it was already gone or replaced. Holding the change here instead keeps the editor's image state
//  purely in memory until Save, when the owning view model applies it alongside the database write.
//

import Foundation
import SaltyCore

/// What the editor wants done with the recipe's image when it is saved.
enum PendingRecipeImage: Equatable {
    /// Leave the stored image as it is.
    case unchanged
    /// Replace (or add) the image with these bytes.
    case replace(Data)
    /// Remove the stored image.
    case remove

    /// True when saving would change the image, for "unsaved changes" prompts.
    var isChange: Bool {
        self != .unchanged
    }

    /// The image bytes the editor should show: the pending replacement, nothing after a pending
    /// removal, or the stored image when nothing is pending.
    func previewData(for recipe: Recipe) -> Data? {
        switch self {
        case .unchanged:
            return recipe.fullImageData
        case .replace(let data):
            return data
        case .remove:
            return nil
        }
    }

    /// Applies the change to `recipe`: writes the replacement's file and points the recipe at it, or
    /// clears the recipe's image reference. Meant to be called immediately before the recipe is
    /// written to the database; the file the recipe *used* to reference is left in place until the
    /// caller commits and deletes it (see `Recipe.deleteStaleImageFiles()`), so a failed write never
    /// costs the old image.
    ///
    /// Returns false when a replacement could not be written to disk, in which case `recipe` is
    /// untouched and the caller should not proceed with the save.
    func apply(to recipe: inout Recipe) -> Bool {
        switch self {
        case .unchanged:
            return true
        case .replace(let data):
            recipe.setImage(data)
            return recipe.imageFilename != nil
        case .remove:
            recipe.removeImage()
            return true
        }
    }
}
