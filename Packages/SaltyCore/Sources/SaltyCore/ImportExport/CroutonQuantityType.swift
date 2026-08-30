//
//  CroutonQuantityType.swift
//  SaltyCore
//
//  Created by Robert on 8/15/26.
//

import Foundation

/// The `quantity.quantityType` tokens Crouton writes into a `.crumb` export.
///
/// Crouton keeps quantity, unit, and ingredient name in separate fields; Salty stores an ingredient as
/// one line of text, so the import has to render the unit itself. Crouton publishes no schema, so only
/// the cases marked below were seen in a real export — the rest are best guesses at Crouton's own
/// spelling. A guess costs nothing: `unitText(forRawType:amount:)` falls back to the raw token
/// (lowercased, underscores turned into spaces) for anything it doesn't recognize.
public enum CroutonQuantityType: String, CaseIterable, Sendable {
    // Seen in a real export:
    case section = "SECTION"
    case item = "ITEM"
    case cup = "CUP"
    case teaspoon = "TEASPOON"
    case tablespoon = "TABLESPOON"
    case ounce = "OUNCE"
    case pound = "POUND"
    case grams = "GRAMS"
    case pinch = "PINCH"
    case can = "CAN"
    case bunch = "BUNCH"

    // Not seen in the sample export, but plausible Crouton spellings; harmless if never matched.
    case kilogram = "KILOGRAM"
    case milligram = "MILLIGRAM"
    case millilitre = "MILLILITRE"
    case litre = "LITRE"
    case fluidOunce = "FLUID_OUNCE"
    case quart = "QUART"
    case pint = "PINT"
    case gallon = "GALLON"
    case package = "PACKAGE"
    case clove = "CLOVE"
    case slice = "SLICE"
    case piece = "PIECE"
    case dash = "DASH"
    case drop = "DROP"
    case handful = "HANDFUL"
    case stick = "STICK"

    /// Unit text for an ingredient line, or "" when the unit shouldn't be written out.
    ///
    /// `ITEM` is Crouton's "just a count" unit ("3 eggs"), and `SECTION` marks a heading rather than a
    /// real ingredient, so both render as no unit at all. Abbreviations stay as-is; spelled-out units
    /// get pluralized for any amount other than exactly one.
    public func unitText(amount: Double?) -> String {
        switch self {
        case .section, .item: return ""
        case .grams: return "g"
        case .kilogram: return "kg"
        case .milligram: return "mg"
        case .millilitre: return "ml"
        case .litre: return "L"
        case .teaspoon: return "tsp"
        case .tablespoon: return "Tbsp"
        case .ounce: return "oz"
        case .fluidOunce: return "fl oz"
        case .pound: return "lb"
        case .quart: return "qt"
        case .pint: return "pt"
        case .gallon: return "gal"
        case .cup: return Self.pluralized("cup", amount: amount)
        case .can: return Self.pluralized("can", amount: amount)
        case .package: return Self.pluralized("package", amount: amount)
        case .clove: return Self.pluralized("clove", amount: amount)
        case .slice: return Self.pluralized("slice", amount: amount)
        case .piece: return Self.pluralized("piece", amount: amount)
        case .drop: return Self.pluralized("drop", amount: amount)
        case .handful: return Self.pluralized("handful", amount: amount)
        case .stick: return Self.pluralized("stick", amount: amount)
        case .pinch: return Self.pluralized("pinch", amount: amount, plural: "pinches")
        case .bunch: return Self.pluralized("bunch", amount: amount, plural: "bunches")
        case .dash: return Self.pluralized("dash", amount: amount, plural: "dashes")
        }
    }

    /// Unit text for a raw Crouton token, tolerating tokens this enum doesn't know.
    public static func unitText(forRawType rawType: String, amount: Double?) -> String {
        let token = rawType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !token.isEmpty else { return "" }
        if let known = CroutonQuantityType(rawValue: token) {
            return known.unitText(amount: amount)
        }
        return token.lowercased().replacing("_", with: " ")
    }

    /// True when the token marks an ingredient-list heading rather than an ingredient.
    public static func isSection(rawType: String?) -> Bool {
        guard let rawType else { return false }
        return rawType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == Self.section.rawValue
    }

    /// Recipe convention pluralizes only above one — "1/2 cup", "1 cup", "3 cups". A missing amount
    /// stays singular, since there's no quantity to agree with.
    private static func pluralized(_ singular: String, amount: Double?, plural: String? = nil) -> String {
        guard let amount, amount > 1 else { return singular }
        return plural ?? singular + "s"
    }
}
