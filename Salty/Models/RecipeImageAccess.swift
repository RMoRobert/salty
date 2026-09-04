//
//  RecipeImageAccess.swift
//  Salty
//
//  The half of `Recipe` that can't live in SaltyCore: reading and writing a recipe's image file.
//
//  Image bytes are stored outside the database, in a `recipeImages` folder beside the .sqlite, and
//  reached through `RecipeImageManager` / `FileManager.saltyImageFolderUrl` -- both of which resolve
//  a location the *app* owns (its container, or a user-granted security-scoped folder). SaltyCore
//  deliberately knows nothing about that, so these stay here as an extension on the shared model type.
//
//  Ordering rule for anything that changes a recipe's image: write the new file, write the database
//  row, and only THEN delete whatever file the row used to point at (`deleteStaleImageFiles()`).
//  Nothing here deletes a file, so a failed database write can never leave a row referencing an
//  image that is already gone.
//

import Foundation
import SaltyCore

extension Recipe {
    /// Loads the full image data from external storage
    var fullImageData: Data? {
        guard let filename = imageFilename else { return nil }
        return RecipeImageManager.shared.loadImage(filename: filename)
    }

    /// Gets the URL for the full image from external storage
    var fullImageURL: URL? {
        guard let filename = imageFilename else { return nil }
        return FileManager.saltyImageFolderUrl.appending(component: filename)
    }

    /// Sets the image: writes `imageData` to external storage, generates the thumbnail, and points
    /// this recipe at the new file. Passing nil clears the reference instead (see `removeImage()`).
    ///
    /// On failure to write the file, the recipe is left unchanged. The previous image file, if its
    /// name differs from the new one, stays on disk until `deleteStaleImageFiles()` runs after the
    /// recipe has been saved.
    mutating func setImage(_ imageData: Data?) {
        if let imageData = imageData {
            if let result = RecipeImageManager.shared.saveImage(imageData, for: id) {
                self.imageFilename = result.filename
                self.imageThumbnailData = result.thumbnailData
                self.lastModifiedImageDate = Date() // Image-only change: bump the image date, NOT lastModifiedDate
            }
        } else {
            removeImage()
        }
    }

    /// Clears this recipe's image reference and thumbnail. The file itself is not touched here; call
    /// `deleteStaleImageFiles()` once the recipe has been saved without it.
    mutating func removeImage() {
        self.imageFilename = nil
        self.imageThumbnailData = nil
        self.lastModifiedImageDate = Date() // Image-only change (removal): bump the image date only
    }

    /// Deletes every image file stored for this recipe other than the one it currently references.
    /// Call after the recipe has been committed to the database, never before.
    func deleteStaleImageFiles() {
        RecipeImageManager.shared.deleteImages(for: id, except: imageFilename)
    }
}
