//
//  RecipeImageManager.swift
//  Salty
//
//  Created by Robert on 7/5/25.
//

import OSLog
import Foundation
import ImageIO
import SQLiteData
import GRDB
import SaltyCore

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
// race will compile silently. Guard it with a lock/actor, isolate to an actor or @MainActor, or
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
    
    // MARK: - Filename safety

    /// Whether `name` can be used as a single file name inside the images directory (see
    /// `LibraryFilenames.isSafeComponent`). Every entry point below checks before touching the filesystem.
    static func isSafeFilenameComponent(_ name: String) -> Bool {
        LibraryFilenames.isSafeComponent(name)
    }

    /// Writes `imageData` as this recipe's image and returns the stored filename with a thumbnail.
    ///
    /// The write is atomic and nothing is deleted here: an older file under a different extension
    /// stays until `deleteImages(for:except:)` is called, which callers do only after the database row
    /// pointing at the new file has been committed. A same-extension replacement overwrites in place,
    /// which is the intended outcome of a save.
    func saveImage(_ imageData: Data, for recipeId: String) -> (filename: String, thumbnailData: Data)? {
        guard Self.isSafeFilenameComponent(recipeId) else {
            logger.error("Refusing to save an image for an unsafe recipe id")
            return nil
        }

        // Ensure the images directory exists before saving
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Failed to create images directory: \(error)")
            return nil
        }

        // The file name is the cross-client contract for the photo's format, so it comes from the core's
        // signature sniffer (16 bytes; the old 8-byte check here could never see the HEIC brand and
        // stored iPhone photos as "<id>.jpg" with HEIF bytes inside).
        let fileExtension = ImageDataFormat.detect(imageData)?.fileExtension ?? "jpg"
        let filename = "\(recipeId).\(fileExtension)"
        let fileURL = imagesDirectory.appending(component: filename)

        do {
            // Atomic: written to a temporary file and renamed into place, so a failure mid-write can't
            // leave a truncated image under the final name.
            try imageData.write(to: fileURL, options: .atomic)
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
    
    /// Deletes the image files stored for a recipe (any filename starting with "recipeId."), keeping
    /// only `keep` -- normally the filename the recipe's database row now references, or nil to
    /// remove them all.
    ///
    /// This is the "delete" half of every image change, and it belongs AFTER the database write that
    /// made the change durable: called earlier, a failed write would leave the row pointing at a file
    /// that no longer exists.
    func deleteImages(for recipeId: String, except keep: String?) {
        guard Self.isSafeFilenameComponent(recipeId) else {
            logger.error("Refusing to delete images for an unsafe recipe id")
            return
        }
        let prefix = "\(recipeId)."
        guard let contents = try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) else { return }

        for fileURL in contents where fileURL.isFileURL {
            let filename = fileURL.lastPathComponent
            guard filename.hasPrefix(prefix), filename != keep else { continue }
            do {
                try FileManager.default.removeItem(at: fileURL)
                logger.debug("Deleted old image: \(filename)")
            } catch {
                logger.warning("Could not delete \(filename): \(error.localizedDescription)")
            }
        }
    }
    
    func loadImage(filename: String) -> Data? {
        guard Self.isSafeFilenameComponent(filename) else {
            logger.error("Refusing to load an image with an unsafe filename")
            return nil
        }
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
        guard Self.isSafeFilenameComponent(filename) else {
            logger.error("Refusing to delete an image with an unsafe filename")
            return
        }
        let fileURL = imagesDirectory.appending(component: filename)
        do {
            try FileManager.default.removeItem(at: fileURL)
            logger.debug("Deleted image file: \(filename)")
        } catch {
            logger.debug("Could not delete image \(filename): \(error)")
        }
    }
    
    /// A square, centre-cropped JPEG thumbnail of `imageData`, `size` points on a side at 3x (900 px for the list's
    /// 300-point request), deliberately oversampled so a larger display size later needs no regeneration.
    ///
    /// Decodes through ImageIO's thumbnail path, which reads only as many pixels as the result needs.
    /// Decoding the whole image first (as `UIImage(data:)` / `NSImage(data:)` drawing did) holds every
    /// pixel of a downloaded photo in memory at once, and a large or hostile PNG from a sync could get
    /// the iOS app killed for it. Also honours EXIF orientation, as the old path did.
    func generateThumbnail(from imageData: Data, size: CGSize) -> Data? {
        let pixelWidth = Int(size.width * 3)
        let pixelHeight = Int(size.height * 3)
        guard pixelWidth > 0, pixelHeight > 0,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = sourceProperties[kCGImagePropertyPixelWidth] as? Int,
              let sourceHeight = sourceProperties[kCGImagePropertyPixelHeight] as? Int,
              sourceWidth > 0, sourceHeight > 0 else { return nil }

        // Aspect fill: the shorter side must cover the box, so the longer side is scaled to match.
        let fillScale = max(Double(pixelWidth) / Double(sourceWidth), Double(pixelHeight) / Double(sourceHeight))
        let maxPixelSize = Int((Double(max(sourceWidth, sourceHeight)) * min(fillScale, 1)).rounded(.up))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }

        // Centre the scaled image over the box and let the context clip the overflow.
        let scale = max(Double(pixelWidth) / Double(scaled.width), Double(pixelHeight) / Double(scaled.height))
        let drawWidth = Double(scaled.width) * scale
        let drawHeight = Double(scaled.height) * scale
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))   // under any transparency
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.draw(scaled, in: CGRect(x: (Double(pixelWidth) - drawWidth) / 2,
                                        y: (Double(pixelHeight) - drawHeight) / 2,
                                        width: drawWidth, height: drawHeight))
        guard let thumbnail = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
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
    
}

/// The image files SaltyCore's `ServerSyncEngine` reads and writes during sync.
extension RecipeImageManager: SyncImageStore {}
