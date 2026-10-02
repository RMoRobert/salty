//
//  SchemaOrgRecipeJSONLDImporter.swift
//  Salty
//
//  Created by Robert on 7/14/25.
//
// Purpose: Parse and import https://schema.org/Recipe data from JSON-LD, aiming for AllRecipes compatibility, though
// should be easily extendible to any site or data supporting this standard
//
// Usage Example:
// let importer = SchemaOrgRecipeJSONLDImporter()
// let recipes = importer.parseRecipes(from: htmlString)
// // or
// let recipes = await importer.parseRecipes(from: URL(string: "https://example.com/recipe")!)
//

import Foundation
import SwiftSoup
import UUIDV7
// URLSession lives in a separate module in swift-corelibs-foundation (Windows, Linux, Android).
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The inverse (Recipe -> JSON-LD) lives in SchemaOrgRecipeJSONLDExporter.
// TODO: Also accept raw .json/.jsonld files as an importable type; scanJSONLD(_:) already reads bare
// JSON-LD, it just isn't wired to a file importer yet.
//
// Rules: salty-contract SPEC.md §8 and its `webimport` corpus (SaltyKMP implements the same rules).
// JSONLDDataset finds the recipes, SchemaOrgRecipeReader reads each one.

public class SchemaOrgRecipeJSONLDImporter {

    /// Stateless; a class's implicit init isn't public, so callers outside SaltyCore need this.
    public init() {}
    private let logger = SaltyLogger(subsystem: "Salty", category: "App")

    /// Bounds on untrusted web content (contract WEB-008). Per-field and per-list limits are
    /// `SchemaOrgRecipeReader`'s.
    private enum Limits {
        static let maxInputBytes = 8 * 1024 * 1024      // cap on fetched HTML/JSON-LD payload
        static let maxImageBytes = 20 * 1024 * 1024     // cap on downloaded recipe photo
        static let maxScriptTags = 50                   // JSON-LD <script> blocks read per page
        static let requestTimeout: TimeInterval = 15
    }

    /// A recipe parsed from JSON-LD, together with page metadata that isn't stored on `Recipe` itself.
    public struct ScannedRecipe: Sendable {
        public let recipe: Recipe
        /// The recipe photo's address, absolute and http(s) (contract WEB-022). The import flow
        /// downloads it and makes the app's own thumbnail.
        public let imageURL: String?

        public init(recipe: Recipe, imageURL: String?) {
            self.recipe = recipe
            self.imageURL = imageURL
        }
    }

    // MARK: - Main parsing method

    /// Parses schema.org Recipe data from HTML containing JSON-LD
    /// - Parameter html: HTML content containing JSON-LD script tags
    /// - Returns: Array of Recipe objects found in the HTML
    public func parseRecipes(from html: String) -> [Recipe] {
        scanRecipes(from: html).map(\.recipe)
    }

    /// Every schema.org Recipe on a page, in document order, following salty-contract SPEC.md §8.
    /// - Parameters:
    ///   - html: the page.
    ///   - pageURL: where it came from. Relative addresses resolve against it (WEB-011), and a recipe
    ///     with no `url` of its own (AllRecipes, among others) records it as its source (WEB-020). Only
    ///     http(s) counts: the import browser's bundled `file://` landing page is no recipe's source.
    public func scanRecipes(from html: String, pageURL: String? = nil) -> [ScannedRecipe] {
        // Guard against pathologically large pages before handing them to the HTML parser.
        guard html.utf8.count <= Limits.maxInputBytes else {
            logger.error("HTML input exceeds \(Limits.maxInputBytes) byte limit; refusing to parse")
            return []
        }

        var blocks: [JSONLDValue] = []
        do {
            // WEB-001: the type's MIME essence, whatever its case or parameters.
            let scripts = try SwiftSoup.parse(html).select("script").filter { script in
                let type = (try? script.attr("type")) ?? ""
                let essence = type.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
                return essence.trimmingCharacters(in: .whitespaces).lowercased() == "application/ld+json"
            }
            // WEB-008 counts every JSON-LD block, readable or not; WEB-L01 skips the unreadable ones.
            blocks = scripts.prefix(Limits.maxScriptTags).compactMap { script in
                JSONLDValue.parse(Data(script.data().utf8))
            }
        } catch {
            logger.error("Error parsing HTML: \(error)")
        }

        let recipes = scan(blocks, pageURL: pageURL)
        logger.info("Parsed \(recipes.count) recipes from HTML")
        return recipes
    }

    /// Every schema.org Recipe in a bare JSON-LD document -- the body of one script block, or the
    /// contents of a `.json`/`.jsonld` file.
    public func scanJSONLD(_ data: Data, pageURL: String? = nil) -> [ScannedRecipe] {
        guard data.count <= Limits.maxInputBytes, let document = JSONLDValue.parse(data) else {
            return []
        }
        return scan([document], pageURL: pageURL)
    }

    private func scan(_ blocks: [JSONLDValue], pageURL: String?) -> [ScannedRecipe] {
        let dataset = JSONLDDataset(blocks: blocks)
        let reader = SchemaOrgRecipeReader(dataset: dataset, pageURL: pageURL)
        // A draft, not a row: stamped to whole milliseconds, as every date SaltyCore makes is (DATE-009).
        let now = Date().roundedToWireMillis
        return dataset.recipes().map { reader.recipe(from: $0, now: now) }
    }
}

// MARK: - Convenience extension for URL parsing

public extension SchemaOrgRecipeJSONLDImporter {
    /// Convenience method to parse recipes from a URL
    /// - Parameter url: URL to fetch and parse
    /// - Returns: Array of Recipe objects found at the URL
    func parseRecipes(from url: URL) async -> [Recipe] {
        // Only fetch real web URLs: reject file://, custom schemes, and anything that could coax the app
        // into reading local resources (SSRF-style abuse of an importer that takes an arbitrary URL).
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            logger.error("Refusing to fetch non-http(s) URL: \(url)")
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Limits.requestTimeout

        do {
            // Streamed under the cap on Apple platforms: a page that sends no Content-Length is cut
            // off at the limit rather than buffered in full (see URLSessionByteLimit's known gap).
            let (data, _) = try await URLSession.shared.data(for: request, maxBytes: Limits.maxInputBytes)
            if let html = String(data: data, encoding: .utf8) {
                // The address is passed through so a page that declares no `url` still records where
                // it came from. See scanRecipes(from:pageURL:).
                return scanRecipes(from: html, pageURL: url.absoluteString).map(\.recipe)
            }
        } catch let tooLarge as ResponseTooLargeError {
            logger.error("Page exceeds the \(tooLarge.limit)-byte limit (\(tooLarge.observed) bytes seen); refusing to parse")
        } catch {
            logger.error("Error fetching URL \(url): \(error)")
        }

        return []
    }

    /// Downloads the recipe photo referenced by a JSON-LD `image` URL (see `ScannedRecipe.imageURL`).
    /// Returns the raw image data only if the URL is a real web URL, the payload is within the size
    /// limit, and the bytes carry a known image container signature (rejects HTML error pages and junk;
    /// see `ImageDataFormat`).
    func downloadImageData(from urlString: String) async -> Data? {
        // Same SSRF guard as parseRecipes(from:): the URL comes from untrusted page content.
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            logger.error("Refusing to fetch non-http(s) image URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Limits.requestTimeout

        do {
            // Streamed under the cap; see parseRecipes(from:).
            let (data, _) = try await URLSession.shared.data(for: request, maxBytes: Limits.maxImageBytes)
            guard ImageDataFormat.isRecognisedImage(data) else {
                logger.error("Downloaded image data is not a recognised image container; skipping")
                return nil
            }
            return data
        } catch let tooLarge as ResponseTooLargeError {
            logger.error("Image exceeds the \(tooLarge.limit)-byte limit (\(tooLarge.observed) bytes seen); skipping")
            return nil
        } catch {
            logger.error("Error downloading recipe image: \(error)")
            return nil
        }
    }
}
