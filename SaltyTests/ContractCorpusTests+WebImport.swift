//
//  ContractCorpusTests+WebImport.swift
//  SaltyTests
//
//  The corpus's `webimport` suite (salty-contract SPEC.md §8), op `scan_web_recipes`: build the page a
//  case describes, read it with SaltyCore's SchemaOrgRecipeJSONLDImporter, and compare the fields the
//  case names. The expectation format is described in the suite's own `description`.
//

import Testing
import Foundation
import SaltyCore

extension ContractCorpusTests {

    func assertWebImport(_ c: CorpusCase) throws {
        let scanned = SchemaOrgRecipeJSONLDImporter().scanRecipes(from: try page(c), pageURL: c.input["page_url"]?.stringValue)
        let expected = c.expect["recipes"]?.arrayValue ?? []

        #expect(scanned.count == expected.count,
                "\(c.because)\n  expected \(expected.count) recipes, found \(scanned.map(\.recipe.name))")
        for (index, (actual, want)) in zip(scanned, expected).enumerated() {
            compare(actual, want, "\(c.because)\n  [recipe \(index)]")
        }
    }

    /// The page: `html` verbatim, or each of `blocks` (raw text) / the one `jsonld` value as a JSON-LD
    /// script in a minimal document.
    private func page(_ c: CorpusCase) throws -> String {
        if let html = c.input["html"]?.stringValue {
            return html
        }
        let blocks: [String]
        if let listed = c.input["blocks"] {
            blocks = listed.arrayValue.compactMap(\.stringValue)
        } else if let value = c.input["jsonld"] {
            blocks = [try jsonText(value)]
        } else {
            throw CorpusError.message("\(c.id): input has none of html, blocks, jsonld")
        }
        let scripts = blocks.map { #"<script type="application/ld+json">"# + $0 + "</script>" }.joined()
        return "<html><head>" + scripts + "</head><body></body></html>"
    }

    private func compare(_ actual: SchemaOrgRecipeJSONLDImporter.ScannedRecipe, _ want: JSONValue, _ because: String) {
        guard case .object(let fields) = want else {
            Issue.record("\(because): an expected recipe must be an object")
            return
        }
        let recipe = actual.recipe

        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            let label = "\(because) [\(key)]"
            switch key {
            case "name": #expect(recipe.name == value.stringValue, "\(label)")
            case "introduction": #expect(recipe.introduction == value.stringValue, "\(label)")
            case "source": #expect(recipe.source == value.stringValue, "\(label)")
            case "source_details": #expect(recipe.sourceDetails == value.stringValue, "\(label)")
            case "yield": #expect(recipe.yield == value.stringValue, "\(label)")
            case "servings": #expect(recipe.servings == value.intValue, "\(label)")
            case "image_url": #expect(actual.imageURL == value.stringValue, "\(label)")
            case "ingredients": #expect(recipe.ingredients.map(\.text) == value.arrayValue.compactMap(\.stringValue), "\(label)")
            case "ingredient_count": #expect(recipe.ingredients.count == value.intValue, "\(label)")
            case "direction_count": #expect(recipe.directions.count == value.intValue, "\(label)")
            case "directions":
                // A heading and a step with the same words are different rows, so they are told apart here.
                let rows = recipe.directions.map { $0.isHeading == true ? "[heading] \($0.text)" : $0.text }
                let expected = value.arrayValue.map { row in
                    row["heading"].flatMap(\.stringValue).map { "[heading] \($0)" } ?? row.stringValue ?? ""
                }
                #expect(rows == expected, "\(label)")
            case "prep_times":
                let times = recipe.preparationTimes.map { [$0.type, $0.timeString] }
                #expect(times == value.arrayValue.map { $0.arrayValue.compactMap(\.stringValue) }, "\(label)")
            case "nutrition":
                compareNutrition(recipe.nutrition, value, label)
            default:
                Issue.record("\(label): not a field this runner knows. A typo in the corpus, or a new field to map.")
            }
        }
    }

    /// `null` for none; otherwise every listed field present and equal (numbers within 0.01), and every
    /// other field absent.
    private func compareNutrition(_ actual: NutritionInformation?, _ want: JSONValue, _ label: String) {
        guard case .object(let fields) = want else {
            #expect(actual == nil, "\(label): expected no nutrition, got \(String(describing: actual))")
            return
        }
        guard let actual else {
            Issue.record("\(label): expected nutrition, got none")
            return
        }

        let numbers: [String: Double?] = [
            "calories": actual.calories, "carbohydrates": actual.carbohydrates, "cholesterol": actual.cholesterol,
            "fat": actual.fat, "fiber": actual.fiber, "protein": actual.protein, "saturated_fat": actual.saturatedFat,
            "sodium": actual.sodium, "sugar": actual.sugar, "trans_fat": actual.transFat, "vitamin_d": actual.vitaminD,
            "calcium": actual.calcium, "iron": actual.iron, "potassium": actual.potassium, "vitamin_a": actual.vitaminA,
            "vitamin_c": actual.vitaminC,
        ]
        for unknown in fields.keys where numbers[unknown] == nil && unknown != "serving_size" {
            Issue.record("\(label).\(unknown): not a nutrition field this runner knows")
        }
        for (name, value) in numbers.sorted(by: { $0.key < $1.key }) {
            if case .number(let expected)? = fields[name] {
                guard let value else {
                    Issue.record("\(label).\(name): expected \(expected), got none")
                    continue
                }
                #expect(abs(value - expected) <= 0.01, "\(label).\(name): expected \(expected), got \(value)")
            } else {
                #expect(value == nil, "\(label).\(name): expected none, got \(String(describing: value))")
            }
        }
        #expect(actual.servingSize == fields["serving_size"]?.stringValue, "\(label).serving_size")
    }

    /// `value` as JSON text, for a `jsonld` case's one block.
    private func jsonText(_ value: JSONValue) throws -> String {
        func plain(_ value: JSONValue) -> Any {
            switch value {
            case .null: return NSNull()
            case .bool(let flag): return flag
            case .number(let number):
                return number.rounded() == number && abs(number) < 1e15 ? Int64(number) as Any : number as Any
            case .string(let text): return text
            case .array(let items): return items.map(plain)
            case .object(let fields): return fields.mapValues(plain)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: plain(value), options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
