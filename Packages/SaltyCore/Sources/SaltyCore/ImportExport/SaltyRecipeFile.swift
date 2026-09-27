//
//  SaltyRecipeFile.swift
//  SaltyCore
//
//  Reading and writing `.saltyRecipe` files: one recipe as a bare object, several as an array, dates as
//  ISO-8601. The format itself is `SaltyRecipeExport`; this is the file around it.
//
//  Reading is forgiving, since files come from every Salty client and version: any date shape a client
//  has written is accepted, and an unreadable recipe in a list is skipped. Writing is Salty's exact shape.
//

import Foundation

public enum SaltyRecipeFile {

    /// The file extension, without the dot.
    public static let fileExtension = "saltyRecipe"

    /// The recipes in a file's contents, in file order. Throws `.empty` for a blank file and
    /// `.notARecipeFile` when nothing readable is in it; an empty list is no recipes, not an error.
    public static func decode(_ data: Data) throws -> [SaltyRecipeExport] {
        guard data.contains(where: { !isWhitespace($0) }) else { throw SaltyRecipeFileError.empty }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(text)"))
            }
            return date
        }

        if let items = try? decoder.decode([LenientRecipe].self, from: data) {
            let recipes = items.compactMap(\.recipe)
            guard !recipes.isEmpty || items.isEmpty else { throw SaltyRecipeFileError.notARecipeFile }
            return recipes
        }
        do {
            return [try decoder.decode(SaltyRecipeExport.self, from: data)]
        } catch {
            throw SaltyRecipeFileError.notARecipeFile
        }
    }

    /// A file's contents: one recipe as a bare object, as Salty shares it, or several as an array. Dates
    /// are whole seconds with a `Z`, the shape the strictest reader (the Apple app's) accepts.
    public static func encode(_ recipes: [SaltyRecipeExport]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return recipes.count == 1 ? try encoder.encode(recipes[0]) : try encoder.encode(recipes)
    }

    /// Any timestamp shape a Salty client has written, or nil.
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let date = SyncWireDate.date(from: trimmed) { return date }
        // Milliseconds and no zone (older SaltyKMP): the wire parser wants the zone, and these meant UTC.
        let hasZone = trimmed.hasSuffix("Z") || trimmed.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        return hasZone ? nil : SyncWireDate.date(from: trimmed + "Z")
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }

    /// One list element, nil when unreadable, so one bad entry doesn't fail the whole file.
    private struct LenientRecipe: Decodable {
        let recipe: SaltyRecipeExport?

        init(from decoder: any Decoder) throws {
            recipe = try? SaltyRecipeExport(from: decoder)
        }
    }
}
