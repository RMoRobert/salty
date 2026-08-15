//
//  SyncImagePreparer.swift
//  Salty
//
//  Image format work for sync, deliberately kept OFF the main actor.
//
//  `SaltySyncService` is `@MainActor` (it's `@Observable` and drives sync UI state), so everything it
//  called synchronously ran on the main thread — including a full decode-and-re-encode of the photo.
//  `ImportFileLimits.maxImageBytes` allows 100 MB, so syncing a large HEIC could hold the main thread
//  for the whole conversion and visibly hang the UI.
//
//  Nothing here touches sync state, the database, or the network: it's `Data` in, `Data` out. The
//  off-main guarantee is stated explicitly rather than relied on as a default, because the default is
//  a moving target:
//
//  - `@concurrent` on `prepare` makes the compiler put the call on the concurrent executor. Without
//    it, a plain non-isolated `async` function happens to run off-actor under this project's Swift 6
//    language mode, but flips to *inheriting the caller's actor* under `NonisolatedNonsendingByDefault`
//    (the direction newer language modes take) — which would silently put the conversion back on the
//    main thread.
//  - `nonisolated` on the enum pins the sync helpers against any future
//    `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` migration, which would otherwise infer @MainActor here.
//
//  `SyncImagePreparerTests` asserts the executor behaviour as a regression guard on top.
//
//  Being free of the @MainActor class also makes the format detection testable, which it wasn't as a
//  private method.
//

import Foundation
import OSLog

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let logger = Logger(subsystem: "Salty", category: "SyncImage")

/// An image ready to be attached to a multipart upload: the bytes to send, and the two strings the
/// request needs to describe them.
struct PreparedSyncImage: Sendable, Equatable {
    let data: Data
    let mimeType: String
    let fileExtension: String
}

nonisolated enum SyncImagePreparer {

    /// Detects the image type from its header bytes, converting to a format the Salty Server accepts
    /// when the original isn't one. Formats the server handles (PNG/JPEG/GIF) pass through untouched,
    /// so the common case copies nothing.
    ///
    /// `@concurrent` on purpose — see the file header. The work is guaranteed off the calling actor.
    @concurrent static func prepare(_ data: Data) async -> PreparedSyncImage {
        prepareSynchronously(data)
    }

    /// The same work, callable synchronously. Exists for tests that assert on the pure format-detection
    /// behaviour; production code should use `prepare(_:)` so the conversion stays off the main actor.
    static func prepareSynchronously(_ data: Data) -> PreparedSyncImage {
        guard data.count >= 8 else {
            return PreparedSyncImage(data: data, mimeType: "image/jpeg", fileExtension: "jpg")
        }

        let bytes = [UInt8](data.prefix(8))

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return PreparedSyncImage(data: data, mimeType: "image/png", fileExtension: "png")
        }

        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return PreparedSyncImage(data: data, mimeType: "image/jpeg", fileExtension: "jpg")
        }

        // GIF: 47 49 46 38
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
            return PreparedSyncImage(data: data, mimeType: "image/gif", fileExtension: "gif")
        }

        // WebP: 52 49 46 46 ... 57 45 42 50 - convert to JPEG for broader compatibility
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 {
            if let jpegData = convertToJPEG(data) {
                logger.debug("Converted WebP image to JPEG")
                return PreparedSyncImage(data: jpegData, mimeType: "image/jpeg", fileExtension: "jpg")
            }
            // If conversion fails, send as WebP
            return PreparedSyncImage(data: data, mimeType: "image/webp", fileExtension: "webp")
        }

        // HEIC/HEIF: Check for 'ftyp' box - convert to JPEG
        if data.count >= 12 {
            let ftypBytes = [UInt8](data[4..<8])
            if ftypBytes[0] == 0x66 && ftypBytes[1] == 0x74 && ftypBytes[2] == 0x79 && ftypBytes[3] == 0x70 {
                // Get the brand to log what type of HEIC it is
                let brandBytes = [UInt8](data[8..<12])
                let brand = String(bytes: brandBytes, encoding: .ascii) ?? "unknown"
                logger.debug("Detected HEIC/HEIF image with brand: \(brand)")

                // Convert HEIC to PNG for Salty Server compatibility
                if let pngData = convertToPNG(data) {
                    logger.info("Converted HEIC image to PNG (\(data.count) bytes -> \(pngData.count) bytes)")
                    return PreparedSyncImage(data: pngData, mimeType: "image/png", fileExtension: "png")
                } else {
                    logger.error("Failed to convert HEIC image to PNG - image may not display on server")
                }
            }
        }

        // Unknown format - try to convert to JPEG
        let hexHeader = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug("Unknown image format, header: \(hexHeader), attempting JPEG conversion")

        if let jpegData = convertToJPEG(data) {
            logger.info("Converted unknown format to JPEG (\(data.count) bytes -> \(jpegData.count) bytes)")
            return PreparedSyncImage(data: jpegData, mimeType: "image/jpeg", fileExtension: "jpg")
        }

        // Fallback: send as-is - but log a warning since this may not work
        logger.warning("Could not convert image to JPEG, sending original data (\(data.count) bytes) - may not display correctly")
        return PreparedSyncImage(data: data, mimeType: "application/octet-stream", fileExtension: "bin")
    }

    /// Converts image data to JPEG format
    static func convertToJPEG(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            logger.warning("UIImage failed to load image data (\(data.count) bytes)")
            return nil
        }
        guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
            logger.warning("Failed to convert UIImage to JPEG")
            return nil
        }
        return jpegData
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            logger.warning("NSImage failed to load image data (\(data.count) bytes)")
            return nil
        }
        guard let tiffData = image.tiffRepresentation else {
            logger.warning("Failed to get TIFF representation from NSImage")
            return nil
        }
        guard let bitmap = NSBitmapImageRep(data: tiffData) else {
            logger.warning("Failed to create NSBitmapImageRep from TIFF data")
            return nil
        }
        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            logger.warning("Failed to create JPEG representation from bitmap")
            return nil
        }
        return jpegData
        #else
        logger.warning("No image conversion available on this platform")
        return nil
        #endif
    }

    /// Converts image data to PNG format
    static func convertToPNG(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            logger.warning("UIImage failed to load image data (\(data.count) bytes)")
            return nil
        }
        guard let pngData = image.pngData() else {
            logger.warning("Failed to convert UIImage to PNG")
            return nil
        }
        return pngData
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            logger.warning("NSImage failed to load image data (\(data.count) bytes)")
            return nil
        }
        guard let tiffData = image.tiffRepresentation else {
            logger.warning("Failed to get TIFF representation from NSImage")
            return nil
        }
        guard let bitmap = NSBitmapImageRep(data: tiffData) else {
            logger.warning("Failed to create NSBitmapImageRep from TIFF data")
            return nil
        }
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            logger.warning("Failed to create PNG representation from bitmap")
            return nil
        }
        return pngData
        #else
        logger.warning("No image conversion available on this platform")
        return nil
        #endif
    }
}
