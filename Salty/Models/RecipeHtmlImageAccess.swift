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
import ImageIO
import UniformTypeIdentifiers
import SaltyCore

extension Recipe {
    /// Default-options HTML for this recipe, photo included.
    var asHtml: String {
        asHtmlWithOptions(options: HTMLExportOptions())
    }

    public var imageAsBase64: String? {
        // Modified from https://www.reddit.com/r/iOSProgramming/comments/10odrf5/convert_coregraphics_cgimage_and_base64_string
        guard let imageData = fullImageData else {
            return nil
        }
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        // For compression, but unsure if need to manually "releae" CFDictionary, and default is easier for now (and may be perfectly fine)
        //let properties: [CFString : Any] = ([kCGImageDestinationLossyCompressionQuality: 0.8 as CFNumber] as CFDictionary) as! [CFString : Any]
        guard let mutableData = CFDataCreateMutable(nil, 0),
              //let dest = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, properties as CFDictionary)
              let dest = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            return nil
        }
        let data = mutableData as Foundation.Data
        return data.base64EncodedString()
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
