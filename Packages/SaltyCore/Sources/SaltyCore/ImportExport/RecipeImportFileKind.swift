//
//  RecipeImportFileKind.swift
//  SaltyCore
//
//  Created by Robert on 8/15/26.
//

import Foundation

/// The recipe file formats Salty can import, identified by file extension.
///
/// Lives here (rather than in the import view) so the file-type detection the picker relies on is
/// testable on its own.
public enum RecipeImportFileKind: String, CaseIterable, Identifiable, Sendable {
    case saltyRecipe
    case macGourmet
    case crouton

    public var id: String { rawValue }

    public init?(fileExtension: String) {
        switch fileExtension.trimmingCharacters(in: .whitespaces).lowercased() {
        case "saltyrecipe": self = .saltyRecipe
        // .mgourmet ONLY — do not "helpfully" add .mgourmet3/.mgourmet4 here. MacGourmet exports
        // several plist flavors that share an outer shape but not their keys: `.mgourmet` carries a
        // flat `INGREDIENTS` array, while `.mgourmet4` carries `INGREDIENTS_TREE` instead and omits
        // `INGREDIENTS` entirely. Because every field on `MacGourmetImportRecipe` is optional, a
        // .mgourmet4 file decodes without error and imports every recipe with *zero* ingredients
        // (verified against a real 79-recipe export). Failing the file-type check is the honest
        // outcome until the importer reads `INGREDIENTS_TREE`.
        case "mgourmet": self = .macGourmet
        case "crumb": self = .crouton
        default: return nil
        }
    }

    public init?(url: URL) {
        self.init(fileExtension: url.pathExtension)
    }

    /// Format name shown next to a selected file.
    public var displayName: String {
        switch self {
        case .saltyRecipe: return "Salty"
        case .macGourmet: return "MacGourmet"
        case .crouton: return "Crouton"
        }
    }

    /// Extensions listed for this format in the picker's help text.
    public var fileExtensionsDescription: String {
        switch self {
        case .saltyRecipe: return ".saltyRecipe"
        case .macGourmet: return ".mgourmet"
        case .crouton: return ".crumb"
        }
    }
}
