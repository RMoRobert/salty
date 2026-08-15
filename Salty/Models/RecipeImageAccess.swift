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
    
    /// Sets the image data, saving to external storage and generating thumbnail
    mutating func setImage(_ imageData: Data?) {
        if let imageData = imageData {
            if let result = RecipeImageManager.shared.saveImage(imageData, for: id) {
                self.imageFilename = result.filename
                self.imageThumbnailData = result.thumbnailData
                self.lastModifiedImageDate = Date() // Image-only change: bump the image date, NOT lastModifiedDate
            }
        } else {
            // Remove existing image
            if let filename = imageFilename {
                RecipeImageManager.shared.deleteImage(filename: filename)
            }
            self.imageFilename = nil
            self.imageThumbnailData = nil
            self.lastModifiedImageDate = Date() // Image-only change (removal): bump the image date only
        }
    }

    /// Removes the image and cleans up external storage
    mutating func removeImage() {
        if let filename = imageFilename {
            RecipeImageManager.shared.deleteImage(filename: filename)
        }
        self.imageFilename = nil
        self.imageThumbnailData = nil
        self.lastModifiedImageDate = Date() // Image-only change (removal): bump the image date only
    }
    
}
