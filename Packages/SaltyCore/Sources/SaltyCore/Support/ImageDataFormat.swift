//
//  ImageDataFormat.swift
//  SaltyCore
//
//  Recognises an image by its container signature (magic bytes), with no decoder involved, so
//  untrusted downloads (often an HTML error page or empty body) can be rejected before they become a
//  recipe photo. Signature matching rather than ImageIO keeps SaltyCore portable.
//

import Foundation

/// An image container recognised by its leading bytes.
public enum ImageDataFormat: String, Sendable, CaseIterable {
    case jpeg
    case png
    case gif
    case webp
    case heic
    case tiff
    case bmp

    /// The conventional file extension for this format.
    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .gif: "gif"
        case .webp: "webp"
        case .heic: "heic"
        case .tiff: "tif"
        case .bmp: "bmp"
        }
    }
}

extension ImageDataFormat {

    /// The format `data` appears to be, or nil if its leading bytes match no known image container.
    /// Reads at most the first 16 bytes.
    public static func detect(_ data: Data) -> ImageDataFormat? {
        // A prefix copy keeps indexing 0-based; `data` may be a slice whose startIndex isn't 0.
        let head = [UInt8](data.prefix(16))

        // JPEG: SOI marker.
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }

        // PNG: 8-byte signature.
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }

        // GIF: "GIF87a" / "GIF89a".
        if head.starts(with: Array("GIF87a".utf8)) || head.starts(with: Array("GIF89a".utf8)) { return .gif }

        // TIFF: byte-order mark plus the 42 magic, in whichever endianness.
        if head.starts(with: [0x49, 0x49, 0x2A, 0x00]) || head.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }

        // BMP: "BM". Only two bytes, so require a plausible file-size field behind it rather than
        // calling every text file starting "BM…" an image.
        if head.starts(with: Array("BM".utf8)) && head.count >= 6 { return .bmp }

        // RIFF containers: "RIFF" <4-byte size> "WEBP".
        if head.count >= 12, head.starts(with: Array("RIFF".utf8)), Array(head[8..<12]) == Array("WEBP".utf8) {
            return .webp
        }

        // ISO base media (HEIC/HEIF/AVIF): a box length, then "ftyp", then a brand. Matching on "ftyp"
        // alone would also catch MP4 video, so the brand is checked too.
        if head.count >= 12, Array(head[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: head[8..<12], as: UTF8.self)
            if ["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs",
                "mif1", "msf1", "avif", "avis"].contains(brand) {
                return .heic
            }
        }

        return nil
    }

    /// Whether `data` looks like a real image file rather than an HTML error page, an empty body or junk.
    public static func isRecognisedImage(_ data: Data) -> Bool {
        detect(data) != nil
    }
}
