//
//  RecipeHtmlImageAccess.swift
//  Salty
//
//  The image half of HTML export, which SaltyCore can't do for itself.
//
//  Rendering a recipe to HTML is pure -- except for inlining the photo, which means reading bytes from
//  the app-owned image folder (see RecipeImageAccess.swift). So SaltyCore's `asHtmlWithOptions` takes
//  the base64 photo as a parameter, and the overload below supplies it. Call sites are unchanged:
//  omitting `imageBase64:` resolves to this overload, which is what every caller in the app and the
//  tests already writes.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SQLiteData
import SaltyCore

extension Recipe {
    /// Default-options HTML for this recipe, photo included.
    var asHtml: String {
        asHtmlWithOptions(options: HTMLExportOptions())
    }

    public var imageAsBase64: String? {
        Self.jpegBase64(from: fullImageData, grayscale: false)
    }

    /// The photo as base64 JPEG, optionally desaturated (for grayscale printing — WebKit drops CSS image
    /// filters when paginating to PDF, so the pixels themselves have to be gray).
    func imageAsBase64(grayscale: Bool) -> String? {
        Self.jpegBase64(from: fullImageData, grayscale: grayscale)
    }

    /// Re-encodes `imageData` (any ImageIO-readable format) as base64 JPEG, converting to grayscale on request.
    static func jpegBase64(from imageData: Data?, grayscale: Bool) -> String? {
        guard let imageData,
              let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              var cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        if grayscale, let gray = Self.grayscaleCopy(of: cgImage) {
            cgImage = gray
        }
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            return nil
        }
        return (mutableData as Foundation.Data).base64EncodedString()
    }

    /// `image` redrawn into an 8-bit device-gray bitmap.
    private static func grayscaleCopy(of image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// This recipe as one page of a `RecipeHtmlDocument`: photo inlined, course / category / tag names
    /// resolved from the library.
    /// - Parameter grayscaleImage: desaturate the photo (grayscale printing).
    func htmlPage(database: any DatabaseReader, grayscaleImage: Bool = false) -> RecipeHtmlPage {
        let names = libraryNames(database: database)
        return RecipeHtmlPage(recipe: self, course: names.course, categories: names.categories, tags: names.tags,
                              imageBase64: imageAsBase64(grayscale: grayscaleImage))
    }

    /// Renders to HTML with the recipe's own photo inlined.
    func asHtmlWithOptions(
        options: HTMLExportOptions,
        theme: RecipeHtmlTheme = .modern,
        course: String? = nil,
        categories: [String] = [],
        tags: [String] = []
    ) -> String {
        asHtmlWithOptions(
            options: options,
            theme: theme,
            course: course,
            categories: categories,
            tags: tags,
            imageBase64: imageAsBase64
        )
    }
}
