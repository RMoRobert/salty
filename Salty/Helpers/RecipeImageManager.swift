//
//  RecipeImageManager.swift
//  Salty
//
//  Created by Robert on 7/5/25.
//

import OSLog
import Foundation
import SQLiteData
import GRDB

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif


// MARK: - Image Manager

// Safe to share across tasks: stored state is immutable (logger, imagesDirectory, injected
// database) and file operations use only local state.
//
// ⚠️ `@unchecked` means the compiler does NOT verify this. If you add mutable stored state, the
// race will compile silently — guard it with a lock/actor, isolate to an actor or @MainActor, or
// re-justify this annotation.
final class RecipeImageManager: @unchecked Sendable {
    static let shared = RecipeImageManager()
    private let logger = Logger(subsystem: "Salty", category: "App")
    private let imagesDirectory: URL
    
    @Dependency(\.defaultDatabase) private var database
    
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
    func cleanupOrphanedImages() async {
        do {
            // Check if the images directory exists before attempting cleanup
            guard FileManager.default.fileExists(atPath: imagesDirectory.path) else {
                logger.info("Images directory does not exist, skipping cleanup")
                return
            }
            
            // Get all image filenames from the database
            let referencedFilenames = try await database.read { db in
                try String.fetchAll(db, sql: "SELECT imageFilename FROM recipe WHERE imageFilename IS NOT NULL")
            }
            
            // Get all files in the images directory
            let fileManager = FileManager.default
            let imageFiles = try fileManager.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)
                .filter { $0.isFileURL }
                .map { $0.lastPathComponent }
            
            // Find orphaned files (files that exist on disk but are not referenced in the database)
            let orphanedFiles = imageFiles.filter { filename in
                !referencedFilenames.contains(filename)
            }
            
            // Delete orphaned files
            var deletedCount = 0
            for filename in orphanedFiles {
                do {
                    let fileURL = imagesDirectory.appending(component: filename)
                    try fileManager.removeItem(at: fileURL)
                    deletedCount += 1
                    logger.info("Deleted orphaned image file: \(filename)")
                } catch {
                    logger.error("Failed to delete orphaned image file \(filename): \(error)")
                }
            }
            
            if deletedCount > 0 {
                logger.info("Cleanup completed: deleted \(deletedCount) orphaned image files")
            } else {
                logger.info("Cleanup completed: no orphaned image files found")
            }
            
        } catch {
            logger.error("Error during image cleanup: \(error)")
        }
    }
    
    /// Rebuilds the stored preview thumbnail for every recipe whose full image is still on disk.
    ///
    /// Builds before the aspect-fill fix generated iOS thumbnails by stretching the photo to a square,
    /// so libraries created on (or synced from) those versions still hold distorted bitmaps. The
    /// full-resolution images are retained, so regenerating is just re-running `generateThumbnail`.
    /// Bumps `lastModifiedImageDate` — not `lastModifiedDate` — so the corrected thumbnail propagates
    /// on the next sync without looking like a recipe content edit.
    ///
    /// Intended as a temporary one-shot repair tool exposed in Advanced settings; remove once
    /// existing libraries have been migrated.
    /// - Returns: the number of recipes updated, and the number whose image could not be regenerated.
    @discardableResult
    func regenerateAllThumbnails() async -> (updated: Int, failed: Int) {
        var updated = 0
        var failed = 0
        do {
            let recipes: [(id: String, filename: String)] = try await database.read { db in
                try Row.fetchAll(db, sql: "SELECT id, imageFilename FROM recipe WHERE imageFilename IS NOT NULL")
                    .compactMap { row in
                        guard let id: String = row["id"], let filename: String = row["imageFilename"] else { return nil }
                        return (id, filename)
                    }
            }

            for recipe in recipes {
                guard let imageData = loadImage(filename: recipe.filename),
                      let thumbnailData = generateThumbnail(from: imageData, size: CGSize(width: 300, height: 300)) else {
                    failed += 1
                    logger.error("Could not regenerate thumbnail for recipe \(recipe.id) (image '\(recipe.filename)')")
                    continue
                }

                try await database.write { db in
                    try db.execute(sql: """
                        UPDATE recipe
                        SET imageThumbnailData = ?, lastModifiedImageDate = ?
                        WHERE id = ?
                        """,
                        arguments: [thumbnailData, Date(), recipe.id]
                    )
                }
                updated += 1
            }

            logger.info("Thumbnail regeneration completed: \(updated) updated, \(failed) failed")
        } catch {
            logger.error("Error during thumbnail regeneration: \(error)")
        }
        return (updated, failed)
    }

    func saveImage(_ imageData: Data, for recipeId: String) -> (filename: String, thumbnailData: Data)? {
        // Ensure the images directory exists before saving
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Failed to create images directory: \(error)")
            return nil
        }
        
        // Delete any existing images for this recipe (handles extension changes)
        deleteAllImages(for: recipeId)
        
        // Determine file extension from image data
        let fileExtension = determineImageFormat(from: imageData) ?? "jpg"
        let filename = "\(recipeId).\(fileExtension)"
        let fileURL = imagesDirectory.appending(component: filename)
        
        do {
            try imageData.write(to: fileURL)
            logger.debug("Saved image '\(filename)' (\(imageData.count) bytes)")
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
    
    /// Deletes all image files for a given recipe ID (any filename starting with "recipeId.")
    private func deleteAllImages(for recipeId: String) {
        let prefix = "\(recipeId)."
        guard let contents = try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) else { return }
        
        for fileURL in contents where fileURL.isFileURL {
            let filename = fileURL.lastPathComponent
            guard filename.hasPrefix(prefix) else { continue }
            do {
                try FileManager.default.removeItem(at: fileURL)
                logger.debug("Deleted old image: \(filename)")
            } catch {
                logger.warning("Could not delete \(filename): \(error.localizedDescription)")
            }
        }
    }
    
    func loadImage(filename: String) -> Data? {
        let fileURL = imagesDirectory.appending(component: filename)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        
        if !fileExists {
            logger.warning("Image file does not exist: \(fileURL.path)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            logger.debug("Loaded image \(filename): \(data.count) bytes from \(fileURL.path)")
            return data
        } catch {
            logger.error("Could not load image \(filename) from \(fileURL.path): \(error)")
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
            // Aspect-fill (center crop) so non-square photos aren't squashed. Scale the image up so it
            // covers the target box, center it, and let the context clip the overflow. Mirrors the macOS
            // branch below. (Drawing to `size` directly would stretch to fit and distort the image.)
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else {
                image.draw(in: CGRect(origin: .zero, size: size))
                return
            }
            let scale = max(size.width / imageSize.width, size.height / imageSize.height)
            let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let origin = CGPoint(x: (size.width - scaledSize.width) / 2,
                                 y: (size.height - scaledSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: scaledSize))
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
