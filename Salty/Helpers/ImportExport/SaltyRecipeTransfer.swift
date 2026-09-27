//
//  SaltyRecipeTransfer.swift
//  Salty
//
//  The Apple-only half of recipe sharing: the app's declared uniform type identifiers, and the
//  `Transferable` conformance that lets a `SaltyRecipeExport` be AirDropped, shared, or dragged.
//  It lives in the app, not SaltyCore, because these frameworks are Apple-only and `UTType(exportedAs:)`
//  only means something in the process whose Info.plist declares the identifier.
//

import Foundation
import UniformTypeIdentifiers
import CoreTransferable
import SaltyCore

public extension UTType {
    static let saltyRecipe = UTType(exportedAs: "com.inuvro.salty.recipe", conformingTo: .json)
    static let saltyRecipeLibrary = UTType(exportedAs: "com.inuvro.salty.recipeLibrary")
}

extension SaltyRecipeExport: @retroactive Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        // A real .saltyRecipe file is the representation that AirDrops cleanly and lets the receiving
        // device "Open in Salty" (the app registers this UTType in Info.plist). A FileRepresentation is
        // far more reliable for this than CodableRepresentation, which historically failed to populate
        // some share destinations. Plain text is kept as a fallback for Mail/Messages to recipients
        // who don't have Salty.
        FileRepresentation(contentType: .saltyRecipe) { recipe in
            let safeName = recipe.name
                .replacing("/", with: "-")
                .replacing(":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = safeName.isEmpty ? "Recipe" : safeName
            let url = URL.temporaryDirectory.appendingPathComponent(filename, conformingTo: .saltyRecipe)
            // SaltyCore's writer and reader for the format, the ones every import and export uses.
            try SaltyRecipeFile.encode([recipe]).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        } importing: { received in
            guard let recipe = try SaltyRecipeFile.decode(Data(contentsOf: received.file)).first else {
                throw SaltyRecipeFileError.notARecipeFile
            }
            return recipe
        }

        // Fallback: readable plain text for Mail/Messages to recipients without Salty.
        DataRepresentation(contentType: .plainText) { recipe in
            let text = recipe.plainTextRepresentation
            return Data(text.utf8)
        } importing: { data in
            // This probably won't work super-well, but is required and should do *something*:
            let recipe: Recipe = RecipeFromTextParser().parseRecipe(from: String(decoding: data, as: UTF8.self))
            return try SaltyRecipeExport.fromRecipe(recipe)
        }
    }
}
