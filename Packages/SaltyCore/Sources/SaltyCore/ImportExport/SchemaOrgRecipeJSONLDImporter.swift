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
import ImageIO
import OSLog
import UUIDV7

// The inverse (Recipe -> JSON-LD) lives in SchemaOrgRecipeJSONLDExporter.
// TODO: Also accept raw .json/.jsonld files as an importable type (this class currently ingests JSON-LD
// only via HTML/URL; parseJSONLD(_:) already handles bare JSON-LD data if wired to a file importer).

public class SchemaOrgRecipeJSONLDImporter {

    /// Stateless; a class's implicit init isn't public, so callers outside SaltyCore need this.
    public init() {}
    private let logger = Logger(subsystem: "Salty", category: "App")

    /// Reasonable bounds to prevent untruested web content from going rogue; should be generous enough for most real recipes
    private enum Limits {
        static let maxInputBytes = 8 * 1024 * 1024      // cap on fetched HTML/JSON-LD payload
        static let maxImageBytes = 20 * 1024 * 1024     // cap on downloaded recipe photo
        static let maxScriptTags = 50                   // JSON-LD <script> blocks scanned per page
        static let maxFieldLength = 20_000              // per string field (name, instruction, etc.)
        static let maxArrayItems = 1_000                // ingredients / directions / notes per recipe
        static let requestTimeout: TimeInterval = 15
    }

    /// A recipe parsed from JSON-LD, together with page metadata that isn't stored on `Recipe` itself.
    public struct ScannedRecipe: Sendable {
        public let recipe: Recipe
        /// URL of the recipe photo declared in the JSON-LD `image` field, if any. The import flow
        /// downloads this and generates the app's own thumbnail via `RecipeImageManager`.
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

    /// Parses schema.org Recipe data from HTML containing JSON-LD, keeping page metadata
    /// (such as the recipe photo URL) alongside each recipe.
    /// - Parameters:
    ///   - html: HTML content containing JSON-LD script tags
    ///   - pageURL: where the HTML came from, used as `sourceDetails` for a recipe whose JSON-LD
    ///     declares no `url` of its own. Plenty of sites — AllRecipes among them — declare none, and
    ///     the address is the one thing about an imported recipe we always know.
    /// - Returns: Array of scanned recipes found in the HTML
    public func scanRecipes(from html: String, pageURL: String? = nil) -> [ScannedRecipe] {
        var recipes: [ScannedRecipe] = []

        // Guard against pathologically large pages before handing them to the HTML parser.
        guard html.utf8.count <= Limits.maxInputBytes else {
            logger.error("HTML input exceeds \(Limits.maxInputBytes) byte limit; refusing to parse")
            return []
        }

        do {
            let doc = try SwiftSoup.parse(html)
            let scriptTags = try doc.select("script[type=application/ld+json]")

            logger.info("Found \(scriptTags.count) JSON-LD script tags")

            for scriptTag in scriptTags.prefix(Limits.maxScriptTags) {
                let jsonContent = try scriptTag.html()

                if let jsonData = jsonContent.data(using: .utf8) {
                    let parsedRecipes = parseJSONLD(jsonData)
                    recipes.append(contentsOf: parsedRecipes)
                }
            }

        } catch {
            logger.error("Error parsing HTML: \(error)")
        }

        logger.info("Successfully parsed \(recipes.count) recipes from HTML")
        return recipes.map { scanned in
            fillingInSourceDetails(scanned, from: pageURL)
        }
    }

    /// Puts the page's own address into `sourceDetails` when the JSON-LD carried none.
    ///
    /// Only a real web address: the import browser starts on a bundled `file://` landing page, and
    /// recording that as where a recipe came from would be worse than recording nothing.
    private func fillingInSourceDetails(_ scanned: ScannedRecipe, from pageURL: String?) -> ScannedRecipe {
        guard scanned.recipe.sourceDetails.isEmpty,
              let pageURL,
              let scheme = URL(string: pageURL)?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return scanned
        }

        var recipe = scanned.recipe
        recipe.sourceDetails = pageURL
        return ScannedRecipe(recipe: recipe, imageURL: scanned.imageURL)
    }
    
    // MARK: - JSON-LD parsing
    
    private func parseJSONLD(_ jsonData: Data) -> [ScannedRecipe] {
        var recipes: [ScannedRecipe] = []

        do {
            let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
            
            if let jsonDict = json as? [String: Any] {
                // Handle single JSON-LD object
                if let recipe = parseRecipeFromJSONDict(jsonDict) {
                    recipes.append(recipe)
                }
                
                // Handle if nested in @graph array (Cookie and Kate, etc.)
                if let graph = jsonDict["@graph"] as? [[String: Any]] {
                    for item in graph {
                        if let recipe = parseRecipeFromJSONDict(item) {
                            recipes.append(recipe)
                        }
                    }
                }
                // Handle if at top level (AllRecipes, etc.):
            } else if let jsonArray = json as? [[String: Any]] {
                // Handle array of JSON-LD objects
                for item in jsonArray {
                    if let recipe = parseRecipeFromJSONDict(item) {
                        recipes.append(recipe)
                    }
                }
            }
            
        } catch {
            logger.error("Error parsing JSON-LD: \(error)")
        }
        
        return recipes
    }
    
    private func parseRecipeFromJSONDict(_ dict: [String: Any]) -> ScannedRecipe? {
        // Check if this is a Recipe type
        guard isRecipeType(dict) else {
            return nil
        }

        logger.info("Parsing Recipe from JSON-LD")

        let recipe = Recipe(
            id: UUIDV7().uuidString,
            name: extractString(from: dict, key: "name") ?? "",
            createdDate: Date(),
            lastModifiedDate: Date(),
            lastPrepared: nil,
            source: extractAuthor(from: dict),
            sourceDetails: extractString(from: dict, key: "url") ?? "",
            introduction: extractString(from: dict, key: "description") ?? "",
            difficulty: .notSet, // haven't found in format, but is possible?
            //rating: extractRating(from: dict), // probably doesn't make sense; want user-supplied rating, if any
            rating: .notSet,
            imageFilename: nil,
            imageThumbnailData: nil,
            // The photo is attached later by the import flow, which downloads ScannedRecipe.imageURL
            // and generates our own thumbnail via RecipeImageManager. Site-provided thumbnail data is
            // intentionally not used, so all thumbnails are created consistently.
            isFavorite: false,
            wantToMake: false,
            yield: extractString(from: dict, key: "recipeYield") ?? "",
            servings: extractServings(from: dict),
            directions: extractDirections(from: dict),
            ingredients: extractIngredients(from: dict),
            notes: extractNotes(from: dict),
            preparationTimes: extractPreparationTimes(from: dict),
            nutrition: extractNutritionInformation(from: dict)
        )

        return ScannedRecipe(recipe: recipe, imageURL: extractImageURL(from: dict))
    }
    
    // MARK: - Type checking
    
    private func isRecipeType(_ dict: [String: Any]) -> Bool {
        guard let type = dict["@type"] else {
            return false
        }
        
        // Handle string type
        if let typeString = type as? String {
            return typeString == "Recipe"
        }
        
        // Handle array of types
        if let typeArray = type as? [String] {
            return typeArray.contains("Recipe")
        }
        
        return false
    }
    
    // MARK: - Data extraction methods
    
    private func extractString(from dict: [String: Any], key: String) -> String? {
        if let value = dict[key] as? String {
            return decodeHTMLEntities(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
    
    /// Decodes the HTML character references that appear in JSON-LD data, and clamps the result so a
    /// single oversized field can't blow up memory or downstream rendering.
    ///
    /// See `HTMLEntities.decode` for why this is one real pass over the text rather than the chain of
    /// replacements it used to be: the chain could only decode the entities it listed, and every recipe
    /// plugin writes its fractions as `&#8531;`.
    private func decodeHTMLEntities(_ text: String) -> String {
        // Trimmed AFTER decoding, not just before: a field that is nothing but `&nbsp;` should end up
        // empty rather than blank-looking, and the KMP and .NET importers do it in that order too.
        let decoded = HTMLEntities.decode(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.count > Limits.maxFieldLength ? String(decoded.prefix(Limits.maxFieldLength)) : decoded
    }
    
    private func extractAuthor(from dict: [String: Any]) -> String {
        if let author = dict["author"] {
            // Handle string author
            if let authorString = author as? String {
                return decodeHTMLEntities(authorString)
            }
            
            // Handle object author
            if let authorDict = author as? [String: Any] {
                if let name = authorDict["name"] as? String {
                    return decodeHTMLEntities(name)
                }
            }
            
            // Handle array of authors
            if let authorArray = author as? [[String: Any]] {
                let names = authorArray.compactMap { $0["name"] as? String }
                return names.map { decodeHTMLEntities($0) }.joined(separator: ", ")
            }
        }
        
        return ""
    }

// Probably doesn't make sense -- rating in app is user rating, not rating from site?
//    private func extractRating(from dict: [String: Any]) -> Rating {
//        if let aggregateRating = dict["aggregateRating"] as? [String: Any] {
//            if let ratingValue = aggregateRating["ratingValue"] as? Double {
//                // Convert to 1-5 scale
//                let roundedRating = Int(round(ratingValue))
//                return Rating(rawValue: min(max(roundedRating, 0), 5)) ?? .notSet
//            }
//            if let ratingValue = aggregateRating["ratingValue"] as? String,
//               let doubleValue = Double(ratingValue) {
//                let roundedRating = Int(round(doubleValue))
//                return Rating(rawValue: min(max(roundedRating, 0), 5)) ?? .notSet
//            }
//        }
//        return .notSet
//    }
    
    private func extractServings(from dict: [String: Any]) -> Int? {
        // Try recipeYield first
        if let yield = dict["recipeYield"] {
            if let yieldInt = yield as? Int {
                return yieldInt
            }
            if let yieldString = yield as? String {
                // Extract number from string like "4 servings" or "Serves 6"
                let numbers = yieldString.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
                return numbers.first
            }
        }
        
        // Try nutrition servingSize
        if let nutrition = dict["nutrition"] as? [String: Any],
           let servingSize = nutrition["servingSize"] as? String {
            let numbers = servingSize.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            return numbers.first
        }
        
        return nil
    }
    
    private func extractDirections(from dict: [String: Any]) -> [Direction] {
        var directions: [Direction] = []
        
        if let recipeInstructions = dict["recipeInstructions"] {
            if let instructionsArray = recipeInstructions as? [[String: Any]] {
                for instruction in instructionsArray.prefix(Limits.maxArrayItems) {
                    if let text = instruction["text"] as? String {
                        directions.append(Direction(
                            id: UUIDV7().uuidString,
                            isHeading: false,
                            text: decodeHTMLEntities(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        ))
                    }
                }
            } else if let instructionsArray = recipeInstructions as? [String] {
                for instruction in instructionsArray.prefix(Limits.maxArrayItems) {
                    directions.append(Direction(
                        id: UUIDV7().uuidString,
                        isHeading: false,
                        text: decodeHTMLEntities(instruction.trimmingCharacters(in: .whitespacesAndNewlines))
                    ))
                }
            } else if let instructionString = recipeInstructions as? String {
                // Handle single instruction string
                directions.append(Direction(
                    id: UUIDV7().uuidString,
                    isHeading: false,
                    text: decodeHTMLEntities(instructionString.trimmingCharacters(in: .whitespacesAndNewlines))
                ))
            }
        }
        
        return directions
    }
    
    private func extractIngredients(from dict: [String: Any]) -> [Ingredient] {
        var ingredients: [Ingredient] = []
        
        if let recipeIngredients = dict["recipeIngredient"] as? [String] {
            for ingredient in recipeIngredients.prefix(Limits.maxArrayItems) {
                ingredients.append(Ingredient(
                    id: UUIDV7().uuidString,
                    isHeading: false,
                    isMain: false,
                    text: decodeHTMLEntities(ingredient.trimmingCharacters(in: .whitespacesAndNewlines))
                ))
            }
        }
        
        return ingredients
    }
    
    private func extractPreparationTimes(from dict: [String: Any]) -> [PreparationTime] {
        var preparationTimes: [PreparationTime] = []
        
        // Extract prep time
        if let prepTime = dict["prepTime"] as? String {
            let timeString = formatDuration(prepTime)
            preparationTimes.append(PreparationTime(
                id: UUIDV7().uuidString,
                type: "Prep",
                timeString: timeString
            ))
        }
        
        // Extract cook time
        if let cookTime = dict["cookTime"] as? String {
            let timeString = formatDuration(cookTime)
            preparationTimes.append(PreparationTime(
                id: UUIDV7().uuidString,
                type: "Cook",
                timeString: timeString
            ))
        }
        
        // Extract total time
        if let totalTime = dict["totalTime"] as? String {
            let timeString = formatDuration(totalTime)
            preparationTimes.append(PreparationTime(
                id: UUIDV7().uuidString,
                type: "Total",
                timeString: timeString
            ))
        }
        
        return preparationTimes
    }
    
    private func extractImageURL(from dict: [String: Any]) -> String? {
        // Handle image field
        if let image = dict["image"] {
            // Handle string URL
            if let imageString = image as? String {
                return imageString
            }
            
            // Handle object with URL property
            if let imageDict = image as? [String: Any] {
                if let url = imageDict["url"] as? String {
                    return url
                }
            }
            
            // Handle array of images (take first one)
            if let imageArray = image as? [Any] {
                if let firstImage = imageArray.first {
                    if let imageString = firstImage as? String {
                        return imageString
                    }
                    if let imageDict = firstImage as? [String: Any],
                       let url = imageDict["url"] as? String {
                        return url
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractNotes(from dict: [String: Any]) -> [Note] {
        let notes: [Note] = []
        
        // Extract keywords as a note:
//        if let keywords = dict["keywords"] as? String, !keywords.isEmpty {
//            notes.append(Note(
//                id: UUIDV7().uuidString,
//                title: "Keywords",
//                content: keywords
//            ))
//        }
        // TODO: Consider option offering import above as Tags instead?
        
        // Note: schema.org "recipeCategory" is intentionally NOT imported (as a
        // category or a note). Categories are the user's own taxonomy; imported
        // recipes should only get categories the user selects themselves.

        // Extract cuisine as a note
//        if let cuisine = dict["recipeCuisine"] as? String, !cuisine.isEmpty {
//            notes.append(Note(
//                id: UUIDV7().uuidString,
//                title: "Cuisine",
//                content: cuisine
//            ))
        // ^ intentionally not doing now but could
 //       }
       
        return notes
    }
    
    private func extractNutritionInformation(from dict: [String: Any]) -> NutritionInformation? {
        guard let nutrition = dict["nutrition"] as? [String: Any] else {
            return nil
        }
        
        var nutritionInfo = NutritionInformation()
        
        // Extract serving size
        if let servingSize = nutrition["servingSize"] as? String {
            nutritionInfo.servingSize = servingSize
        }
        
        // Extract calories
        if let calories = nutrition["calories"] as? String {
            nutritionInfo.calories = parseNutritionValue(calories)
        }
        
        // Extract macronutrients
        if let protein = nutrition["proteinContent"] as? String {
            nutritionInfo.protein = parseNutritionValue(protein)
        }
        
        if let carbs = nutrition["carbohydrateContent"] as? String {
            nutritionInfo.carbohydrates = parseNutritionValue(carbs)
        }
        
        if let fat = nutrition["fatContent"] as? String {
            nutritionInfo.fat = parseNutritionValue(fat)
        }
        
        if let saturatedFat = nutrition["saturatedFatContent"] as? String {
            nutritionInfo.saturatedFat = parseNutritionValue(saturatedFat)
        }
        
        if let transFat = nutrition["transFatContent"] as? String {
            nutritionInfo.transFat = parseNutritionValue(transFat)
        }
        
        if let fiber = nutrition["fiberContent"] as? String {
            nutritionInfo.fiber = parseNutritionValue(fiber)
        }
        
        if let sugar = nutrition["sugarContent"] as? String {
            nutritionInfo.sugar = parseNutritionValue(sugar)
        }
        
        if let sodium = nutrition["sodiumContent"] as? String {
            nutritionInfo.sodium = parseNutritionValue(sodium)
        }
        
        if let cholesterol = nutrition["cholesterolContent"] as? String {
            nutritionInfo.cholesterol = parseNutritionValue(cholesterol)
        }
        
        // Extract vitamins and minerals
        if let vitaminD = nutrition["vitaminDContent"] as? String {
            nutritionInfo.vitaminD = parseNutritionValue(vitaminD)
        }
        
        if let calcium = nutrition["calciumContent"] as? String {
            nutritionInfo.calcium = parseNutritionValue(calcium)
        }
        
        if let iron = nutrition["ironContent"] as? String {
            nutritionInfo.iron = parseNutritionValue(iron)
        }
        
        if let potassium = nutrition["potassiumContent"] as? String {
            nutritionInfo.potassium = parseNutritionValue(potassium)
        }
        
        if let vitaminA = nutrition["vitaminAContent"] as? String {
            nutritionInfo.vitaminA = parseNutritionValue(vitaminA)
        }
        
        if let vitaminC = nutrition["vitaminCContent"] as? String {
            nutritionInfo.vitaminC = parseNutritionValue(vitaminC)
        }
        
        // Check if we have any nutrition data
        let hasNutritionData = nutritionInfo.calories != nil ||
                              nutritionInfo.protein != nil ||
                              nutritionInfo.carbohydrates != nil ||
                              nutritionInfo.fat != nil ||
                              nutritionInfo.fiber != nil ||
                              nutritionInfo.sugar != nil ||
                              nutritionInfo.sodium != nil ||
                              nutritionInfo.cholesterol != nil ||
                              nutritionInfo.servingSize != nil
        
        return hasNutritionData ? nutritionInfo : nil
    }
    
    private func parseNutritionValue(_ value: String) -> Double? {
        // Pull the leading numeric value out of strings like "240 calories", "9g", "300 mg", "1.5 g".
        // (Extracting the number is unit-agnostic; the previous approach stripped "g" before "mg"/"µg",
        // which mangled "300 mg" into "300 m" and lost every milligram/microgram value.)
        guard let range = value.range(of: #"[-+]?\d*\.?\d+"#, options: .regularExpression) else {
            return nil
        }
        return Double(value[range])
    }
    
    // MARK: - Utility methods
    
    /// Converts ISO 8601 duration (PT15M) to human-readable format
    private func formatDuration(_ duration: String) -> String {
        // Handle ISO 8601 duration format (PT15M, PT1H30M, etc.)
        let cleanDuration = duration.uppercased()
        
        if cleanDuration.hasPrefix("PT") {
            let timeString = String(cleanDuration.dropFirst(2))
            var result: [String] = []
            
            // Extract hours
            if let hourRange = timeString.range(of: "H") {
                let hoursPart = String(timeString[..<hourRange.lowerBound])
                if let hours = Int(hoursPart) {
                    result.append("\(hours) hr")
                }
            }
            
            // Extract minutes
            if let minuteRange = timeString.range(of: "M") {
                let minutesPart = String(timeString[..<minuteRange.lowerBound])
                // Remove hours part if present
                let cleanMinutesPart = minutesPart.components(separatedBy: "H").last ?? minutesPart
                if let minutes = Int(cleanMinutesPart) {
                    result.append("\(minutes) min")
                }
            }
            
            // A duration with nothing but seconds in it ("PT45S") has no hours or minutes to render.
            // Its own text beats a preparation time with no time in it.
            return result.isEmpty ? duration : result.joined(separator: " ")
        }
        
        // Return as-is if not ISO 8601 format
        return duration
    }
}

// MARK: - Convenience extension for URL parsing

public extension SchemaOrgRecipeJSONLDImporter {
    /// Convenience method to parse recipes from a URL
    /// - Parameter url: URL to fetch and parse
    /// - Returns: Array of Recipe objects found at the URL
    public func parseRecipes(from url: URL) async -> [Recipe] {
        // Only fetch real web URLs: reject file://, custom schemes, and anything that could coax the app
        // into reading local resources (SSRF-style abuse of an importer that takes an arbitrary URL).
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            logger.error("Refusing to fetch non-http(s) URL: \(url)")
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Limits.requestTimeout

        do {
            // Streamed under the cap: a page that sends no Content-Length is cut off at the limit
            // rather than buffered in full and measured afterwards.
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
    /// limit, and the data actually decodes as an image (rejects HTML error pages and junk).
    public func downloadImageData(from urlString: String) async -> Data? {
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
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0 else {
                logger.error("Downloaded image data is not a decodable image; skipping")
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
