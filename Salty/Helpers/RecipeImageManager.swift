//
//  RecipeImageManager.swift
//  Salty
//
//  Created by Robert on 7/5/25.
//

import OSLog
import Foundation
import SharingGRDB

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif


// MARK: - Image Manager

class RecipeImageManager {
    static let shared = RecipeImageManager()
    private let logger = Logger(subsystem: "Salty", category: "App")
    private let imagesDirectory: URL
    
    private init() {
        self.imagesDirectory = FileManager.saltyImageFolderUrl
        // Create images directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
            logger.info("Images directory initialized at: \(self.imagesDirectory.path)")
        } catch {
            logger.error("Failed to create images directory during initialization: \(error)")
        }
    }
    
    /// Compares image files in the images directory with database references and deletes orphaned files
    /// This function should be called periodically to clean up unused image files
    func cleanupOrphanedImages() /*async*/ {
        do {
            // Ensure the images directory exists before attempting cleanup
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
            
            // Get all image filenames from the database
            let referencedFilenames =
                Recipe.select {
                        ($0.imageFilename)
                    }
                    .where {
                        ($0.imageFilename != nil)
                    }

            // Get all files in the images directory
            let fileManager = FileManager.default
            let imageFiles = try fileManager.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)
                .filter { $0.isFileURL }
                .map { $0.lastPathComponent }
            
            // TODO: Finish this!
            
//            let orphanedFiles = imageFiles.filter { filename in
//                !referencedFilenames.contains(filename)
//            }
//            
//            // Delete orphaned files
//            var deletedCount = 0
//            for filename in orphanedFiles {
//                do {
//                    let fileURL = imagesDirectory.appending(component: filename)
//                    try fileManager.removeItem(at: fileURL)
//                    deletedCount += 1
//                    logger.info("Deleted orphaned image file: \(filename)")
//                } catch {
//                    logger.error("Failed to delete orphaned image file \(filename): \(error)")
//                }
//            }
//            
//            if deletedCount > 0 {
//                logger.info("Cleanup completed: deleted \(deletedCount) orphaned image files")
//            } else {
//                logger.info("Cleanup completed: no orphaned image files found")
//            }
            
        } catch {
            logger.error("Error during image cleanup: \(error)")
        }
    }
    
    func saveImage(_ imageData: Data, for recipeId: String) -> (filename: String, thumbnailData: Data)? {
        // Ensure the images directory exists before saving
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Failed to create images directory: \(error)")
            return nil
        }
        
        // Determine file extension from image data
        let fileExtension = determineImageFormat(from: imageData) ?? "jpg"
        let filename = "\(recipeId).\(fileExtension)"
        let fileURL = imagesDirectory.appending(component: filename)
        
        do {
            try imageData.write(to: fileURL)
            let thumbnailData = generateThumbnail(from: imageData, size: CGSize(width: 300, height: 300))
            
            // If thumbnail generation fails, create a blank thumbnail or return nil
            if let thumbnailData = thumbnailData {
                return (filename, thumbnailData)
            } else {
                // Create a blank thumbnail as fallback
                let blankThumbnailData = createBlankThumbnail(size: CGSize(width: 300, height: 300))
                return (filename, blankThumbnailData)
            }
        } catch {
            logger.error("Failed to save image for recipe \(recipeId): \(error)")
            return nil
        }
    }
    
    func loadImage(filename: String) -> Data? {
        let fileURL = imagesDirectory.appending(component: filename)
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            logger.debug("Could not load image \(filename): \(error)")
            return nil
        }
    }
    
    func deleteImage(filename: String) {
        let fileURL = imagesDirectory.appending(component: filename)
        do {
            try FileManager.default.removeItem(at: fileURL)
            logger.debug("Deleted image file: \(filename)")
        } catch {
            logger.debug("Could not delete image \(filename): \(error)")
        }
    }
    
    func generateThumbnail(from imageData: Data, size: CGSize) -> Data? {
        #if os(iOS)
        guard let image = UIImage(data: imageData) else { return nil }
        
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnail = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        
        return thumbnail.jpegData(compressionQuality: 0.8)
        
        #elseif os(macOS)
        guard let image = NSImage(data: imageData) else { return nil }
        
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        
        // Calculate center crop to fill the entire thumbnail
        let imageSize = image.size
        let targetSize = size
        
        let imageAspect = imageSize.width / imageSize.height
        let targetAspect = targetSize.width / targetSize.height
        
        var sourceRect: NSRect
        let destRect = NSRect(origin: .zero, size: targetSize)
        
        if imageAspect > targetAspect {
            // Image is wider than target - crop width from center
            let cropWidth = imageSize.height * targetAspect
            let cropX = (imageSize.width - cropWidth) / 2
            sourceRect = NSRect(x: cropX, y: 0, width: cropWidth, height: imageSize.height)
        } else {
            // Image is taller than target - crop height from center
            let cropHeight = imageSize.width / targetAspect
            let cropY = (imageSize.height - cropHeight) / 2
            sourceRect = NSRect(x: 0, y: cropY, width: imageSize.width, height: cropHeight)
        }
        
        // Draw the cropped portion of the image to fill the entire thumbnail
        image.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)
        
        thumbnail.unlockFocus()
        
        guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #endif
    }
    
    func createBlankThumbnail(size: CGSize) -> Data {
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: size)
        let blankImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return blankImage.jpegData(compressionQuality: 0.8) ?? Data()
        
        #elseif os(macOS)
        let blankImage = NSImage(size: size)
        blankImage.lockFocus()
        
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        
        blankImage.unlockFocus()
        
        guard let cgImage = blankImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Data()
        }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) ?? Data()
        #endif
    }
    
    private func determineImageFormat(from data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        
        let bytes = [UInt8](data.prefix(8))
        
        // Check for PNG signature
        if bytes.count >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "png"
        }
        
        // Check for JPEG signature
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8 {
            return "jpg"
        }
        
        // Check for HEIC signature (simplified)
        if bytes.count >= 12 && String(bytes: bytes[4...11], encoding: .ascii)?.contains("ftyp") == true {
            return "heic"
        }
        
        return nil
    }
}
