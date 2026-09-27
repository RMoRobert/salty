//
//  PreparedSyncImage.swift
//  SaltyCore
//
//  An image ready to upload, and the portable way of preparing one.
//

import Foundation

/// An image ready to be attached to a multipart upload: the bytes to send, and the two strings the
/// request needs to describe them.
public struct PreparedSyncImage: Sendable, Equatable {
    public let data: Data
    public let mimeType: String
    public let fileExtension: String

    public init(data: Data, mimeType: String, fileExtension: String) {
        self.data = data
        self.mimeType = mimeType
        self.fileExtension = fileExtension
    }

    /// Labels the bytes by their header without converting anything: the engine's default for
    /// platforms with no image converter. The Apple app passes `SyncImagePreparer` instead, which also
    /// converts HEIC and WebP to formats Salty Server accepts (PNG, JPEG, GIF).
    public static func passThrough(_ data: Data) -> PreparedSyncImage {
        let bytes = [UInt8](data.prefix(8))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return PreparedSyncImage(data: data, mimeType: "image/png", fileExtension: "png")
        }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return PreparedSyncImage(data: data, mimeType: "image/gif", fileExtension: "gif")
        }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            return PreparedSyncImage(data: data, mimeType: "image/webp", fileExtension: "webp")
        }
        // JPEG, and the fallback: the same label SyncImagePreparer gives bytes too short to identify.
        return PreparedSyncImage(data: data, mimeType: "image/jpeg", fileExtension: "jpg")
    }
}
