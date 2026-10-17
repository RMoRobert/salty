//
//  SharedPage.swift
//  SaltyShareExtension
//
//  The web page a host app handed to the share extension.
//

import Foundation
import UniformTypeIdentifiers

enum SharedPage {
    /// The first attachment that is a URL, or failing that, text that reads as one (some browsers share
    /// the address as plain text). Nil when nothing shared is a web address; the caller tells the user.
    @MainActor
    static func url(in context: NSExtensionContext?) async -> URL? {
        let items = (context?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await load(provider, as: .url) {
                return url
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let url = await load(provider, as: .plainText) {
                return url
            }
        }
        return nil
    }

    /// Loads one attachment and reads it as a URL. The completion-handler form rather than the async
    /// one: the item it delivers isn't Sendable, so it is turned into a URL here, where it arrives.
    /// (Main actor like its caller: the provider isn't Sendable either, so it can't change actors.)
    @MainActor
    private static func load(_ provider: NSItemProvider, as type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                continuation.resume(returning: Self.url(from: item))
            }
        }
    }

    private static func url(from item: (any NSSecureCoding)?) -> URL? {
        switch item {
        case let url as URL:
            return url
        case let data as Data:
            // A URL attachment can arrive as its bytes, and text as UTF-8.
            return String(data: data, encoding: .utf8).flatMap(Self.url(fromText:))
        case let text as String:
            return url(fromText: text)
        default:
            return nil
        }
    }

    private static func url(fromText text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        return URL(string: trimmed)
    }
}
