//
//  RecipeSmartParser.swift
//  Salty
//
//  "Smart Parse": turns scanned or pasted recipe text into a structured Recipe with the on-device
//  Apple Intelligence model (Foundation Models framework, iOS/macOS 26+). Nothing leaves the device.
//
//  The model beats RecipeFromTextParser at separating ingredients from steps and re-joining split
//  lines, but invents a yield or serving count when the text has none, so those come from the rules.
//

import Foundation
import FoundationModels
import OSLog
import SaltyCore
import UUIDV7

@available(iOS 26.0, macOS 26.0, *)
struct RecipeSmartParser {

    enum ParseError: Error {
        case modelUnavailable
        /// The text would not fit the model's context window alongside its own reply.
        case textTooLong(limit: Int)
    }

    @Generable(description: "A recipe extracted from the text of a scanned or pasted page")
    struct GeneratedRecipe {
        @Guide(description: "The recipe's title, as written")
        var name: String
        @Guide(description: "Descriptive text about the dish that precedes the ingredients, copied in full; empty if there is none")
        var introduction: String
        @Guide(description: "Every ingredient in order. Copy each one exactly as written, including quantity and unit. A sub-heading such as 'For the sauce' is its own entry marked as a heading.")
        var ingredients: [GeneratedLine]
        @Guide(description: "The cooking steps in order, one step per entry, without step numbers. A sub-heading such as 'To serve' is its own entry marked as a heading.")
        var directions: [GeneratedLine]
        @Guide(description: "Notes, tips or variations that accompany the recipe, one per entry; empty if none")
        var notes: [String]
    }

    @Generable(description: "One ingredient, step, or section heading")
    struct GeneratedLine {
        @Guide(description: "The text of the entry")
        var text: String
        @Guide(description: "True only when the entry is a section heading rather than an ingredient or step")
        var isHeading: Bool
    }

    static let instructions = """
        You extract recipes from text captured by scanning printed or handwritten pages. \
        Keep the original wording and spelling of ingredients and steps; never invent, add, or omit ingredients or steps. \
        The text may come from a page with several columns whose lines were interleaved, and lines may be split mid-sentence: \
        reassemble sentences and lists into their natural order. \
        Ignore page numbers, advertisements, photo captions, and text unrelated to the recipe. \
        If the text contains no recipe, return an empty name and empty lists.
        """

    static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    private let logger = Logger(subsystem: "Salty", category: "SmartParse")

    /// Input budget in characters. The context window also has to hold the instructions, the schema
    /// and the reply, which echoes most of the input, so allow a bit under half of it for input at
    /// roughly four characters per token.
    static func characterLimit(for model: SystemLanguageModel) -> Int {
        max(2_000, Int(Double(model.contextSize - 400) / 2.2 * 4))
    }

    func parseRecipe(from text: String) async throws -> Recipe {
        // Recipes are user content being restructured, which is what the permissive guardrails are for;
        // the default ones refuse ordinary cooking text now and then ("kill the heat", "bloody mary").
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard model.isAvailable else { throw ParseError.modelUnavailable }
        let limit = Self.characterLimit(for: model)
        guard text.count <= limit else { throw ParseError.textTooLong(limit: limit) }

        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let started = Date()
        let response = try await session.respond(
            to: "Extract the recipe from this text:\n\n\(text)",
            generating: GeneratedRecipe.self
        )
        let seconds = Date().timeIntervalSince(started)
        logger.info("Smart parse produced \(response.content.ingredients.count) ingredients and \(response.content.directions.count) directions in \(seconds, format: .fixed(precision: 1))s")
        return Self.recipe(from: response.content, sourceText: text)
    }

    /// Maps the model's reply onto a Recipe. Yield and servings come from the rule-based parser (see
    /// the file comment); so does the name when the model returns none.
    static func recipe(from generated: GeneratedRecipe, sourceText: String) -> Recipe {
        let rules = RecipeFromTextParser().parseRecipe(from: sourceText)
        var recipe = Recipe(id: UUIDV7().uuidString, name: "", createdDate: .now, lastModifiedDate: .now)
        let name = generated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.name = name.isEmpty ? rules.name : name
        recipe.introduction = generated.introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.ingredients = generated.ingredients.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Ingredient(id: UUIDV7().uuidString, isHeading: line.isHeading, isMain: false, text: text)
        }
        recipe.directions = generated.directions.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Direction(id: UUIDV7().uuidString, isHeading: line.isHeading, text: text)
        }
        recipe.notes = generated.notes.compactMap { note in
            let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Note(id: UUIDV7().uuidString, title: "", content: text)
        }
        recipe.yield = rules.yield
        recipe.servings = rules.servings
        return recipe
    }
}
