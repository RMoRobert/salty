//
//  RecipeImageHelper.swift
//  Salty
//
//  Created by Robert on 5/31/23.
//

import Foundation
#if os(OSX)
import AppKit
#else
import UIKit
#endif

extension Recipe {
    
    /**
     Reads image Data from disk for this Recipe object (according to image folder path and imageName property)
     */
    func getImageDataForRecipe() -> Data? {
        guard let imageUrl = getImageUrlForRecipe() else {
            return nil
        }
        guard let data = try? Data(contentsOf: imageUrl) else {
            return nil
        }
        return data
    }
    
    /**
     Fetches image URL (which can be read to get data) for this Recipe object (according to image folder path and imageName property)
     */
    func getImageUrlForRecipe() -> URL? {
        guard let imageFilename = self.imageName else {
            return nil
        }
        let imageUrl = FileManager.saltyImageFolderUrl
            .appendingPathComponent(imageFilename, isDirectory: false)
        return imageUrl
    }
    
    /**
     Writes image data to disk, sets imageName proprety on Recipe object
     */
    func saveImageForRecipe(imageData: Data) -> () {
        let imgName: String = imageName ?? UUID().uuidString
        let imagePath = FileManager.saltyImageFolderUrl
            .appendingPathComponent(imgName, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: FileManager.saltyImageFolderUrl, withIntermediateDirectories: true)
            try imageData.write(to: imagePath)
            let realm = self.realm!.thaw()
            let thawedRecipe = self.thaw()!
            try realm.write {
                thawedRecipe.imageName = imgName
            }
        }
        catch {
            print("Error saving file: \(error)")
            return
        }
    }
    
    // TODO: Do this when recipe removed? possibly also add "cleanup" option?
    func deleteImageForRecipe() -> Bool {
        var wasDeleted = false
        if let imgName = imageName {
            let imagePath = FileManager.saltyImageFolderUrl
                .appendingPathComponent(imgName, isDirectory: false)
            do {
                try FileManager.default.removeItem(at: imagePath)
                wasDeleted = true
                let realm = self.realm!.thaw()
                let thawedRecipe = self.thaw()!
                try realm.write {
                    thawedRecipe.imageName = nil
                }
            }
            catch {
                print("Error removing file: \(error)")
            }
        }
        return wasDeleted
    }
 

    #if os(OSX)
    /**
    Returns NSImage (macOS) or UIImage (iOS, etc.) based on image data saved for this recipe, or nil if none
    */
    func getImageForRecipe() -> NSImage? {
        if let data = getImageDataForRecipe() {
            return NSImage(data: data)
        } else {
            return nil
        }
    }
    #else
    /**
    Returns NSImage (macOS) or UIImage (iOS, etc.) based on image data saved for this recipe, or nil if none
    */
    func getImageForRecipe() -> UIImage? {
        if let data = getImageDataForRecipe() {
            return UIImage(data: data)
        } else {
            return nil
        }
    }
    #endif
}
