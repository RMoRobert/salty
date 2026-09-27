//
//  RecipeImportParser.swift
//  Salty
//
//  Decides how imported text becomes a Recipe: Smart Parse (the on-device model, see
//  RecipeSmartParser) when the OS, the device and the user's setting allow it, otherwise the
//  rule-based RecipeFromTextParser. Any Smart Parse failure falls back to the rules, so an import
//  never blocks on the model.
//

import Foundation
import OSLog
import SaltyCore

enum RecipeImportParser {

    enum Method: Sendable {
        case smart
        case rules
    }

    struct Result: Sendable {
        var recipe: Recipe
        var method: Method
    }

    /// AppStorage key of the user's Smart Parse preference (on by default).
    static let smartParseSettingKey = "smartParseEnabled"

    private static let logger = Logger(subsystem: "Salty", category: "Import")

    /// Whether Smart Parse can run right now: OS 26 or later, eligible hardware, Apple Intelligence on.
    static var isSmartParseAvailable: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return RecipeSmartParser.availability == .available
        }
        return false
    }

    /// A short explanation for the import screen when Smart Parse could work on this device but is
    /// switched off or not ready; nil when it is available or the device can never run it.
    static var smartParseUnavailableHint: String? {
        if #available(iOS 26.0, macOS 26.0, *) {
            switch RecipeSmartParser.availability {
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in system settings to sort scanned text into ingredients and directions automatically."
            case .unavailable(.modelNotReady):
                return "The on-device model is still being prepared; rule-based parsing will be used until it is ready."
            default:
                return nil
            }
        }
        return nil
    }

    static func parse(_ text: String, preferSmart: Bool) async -> Result {
        if preferSmart, #available(iOS 26.0, macOS 26.0, *) {
            do {
                return Result(recipe: try await RecipeSmartParser().parseRecipe(from: text), method: .smart)
            } catch {
                logger.notice("Smart parse unavailable, using rules: \(error)")
            }
        }
        return Result(recipe: RecipeFromTextParser().parseRecipe(from: text), method: .rules)
    }
}
