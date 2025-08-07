//
//  MacGourmetImportRecipe.swift
//  Salty
//
//  Created by Robert on 6/9/23.
//

import Foundation

/// Represents data from MacGourmet (.mgourmet) export file, an XML PList
struct MacGourmetImportRecipe: Decodable {
    var name = ""
    var difficulty: Int?
    var categories: [MGCategory]?
    var directions: [MGDirection]?
    var ingredients: [MGIngredient]?
    var notes: [MGNote]?
    var summary: String?
    var servings: Int?
    var yield: String?
    var image: Data?
    var source: String?
    var url: String?
    var prepTimes: [MGPrepTime]?
    var publicationPage: String?
    var courseName: String?

    
    enum CodingKeys: String, CodingKey {
        case name = "NAME"
        case difficulty = "DIFFICULTY"
        case categories = "CATEGORIES"
        case directions = "DIRECTIONS_LIST"
        case ingredients = "INGREDIENTS"
        case notes = "NOTES_LIST"
        case summary = "SUMMARY"
        case servings = "SERVINGS"
        case yield = "YIELD"
        case image = "IMAGE"
        case source = "SOURCE"
        case url = "URL"
        case prepTimes = "PREP_TIMES"
        case publicationPage = "PUBLICATION_PAGE"
        case courseName = "COURSE_NAME"

    }
    
    struct MGDirection: Decodable {
        var directionText: String?
        var labelText: String?
        
        enum CodingKeys: String, CodingKey {
            case directionText = "DIRECTION_TEXT"
            case labelText = "LABEL_TEXT"
        }
    }
    
    struct MGIngredient: Decodable {
        var description: String?
        var direction: String?
        var isDivider: Bool?
        var isMain: Bool?
        var measurement: String?
        var quantity: String?
        
        enum CodingKeys: String, CodingKey {
            case description = "DESCRIPTION"
            case direction = "DIRECTION"
            case isDivider = "IS_DIVIDER"
            case isMain = "IS_MAIN"
            case measurement = "MEASUREMENT"
            case quantity = "QUANTITY"
        }
    }
    
    struct MGPrepTime: Decodable {
        var amount = 0
        var amount2 = 0
        var timeTypeID = 0
        var timeUnitId = 0
        var timeUnit2Id = 0
        
        enum CodingKeys: String, CodingKey {
            case amount = "AMOUNT"
            case amount2 = "AMOUNT_2"
            case timeTypeID = "TIME_TYPE_ID"
            case timeUnitId = "TIME_UNIT_ID"
            case timeUnit2Id = "TIME_UNIT_2_ID"
        }
        
        var timeString: String {
            var descString = ""
            if amount > 0 {
                descString = "\(amount)"
                if timeUnitId > 0 {
                    if let desc = TimeUnit(rawValue: timeUnitId)?.description {
                        descString += " \(desc)"
                    }
                }
            }
            if amount2 > 0 {
                if amount > 0 {
                    descString += " "
                }
                descString += "\(amount2)"
                if timeUnit2Id > 0 {
                    if let desc = TimeUnit(rawValue: timeUnit2Id)?.description {
                        descString += " \(desc)"
                    }
                }
            }
            return descString
        }
        
        enum TimeType: Int, CustomStringConvertible {
            case other = 0
            case active = 1
            case bake = 2
            case chill = 3
            case cook = 4
            case grill = 7
            case prep = 9
            case rise = 10
            case boil = 18
            case readyIn = 19
            case refrigerate = 21
            case inactive = 28
            case totalTime = 30
            
            var description: String  {
                switch self {
                case .active: return "Active"
                case .bake: return "Bake"
                case .chill: return "Chill"
                case .cook: return "Cook"
                case .grill: return "Grill"
                case .prep: return "Prep"
                case .rise: return "Rise"
                case .boil: return "Boil"
                case .readyIn: return "Ready In"
                case .inactive: return "Inactive"
                case .totalTime: return "Total Time"
                default: return "Other"
                }
            }
        }
        
        public enum TimeUnit: Int, CustomStringConvertible {
            case hours = 1
            case minutes = 2
            case seconds = 3
            case celsius = 5
            case fahrenheit = 6
            case other = 0
            
            var description : String {
                switch self {
                case .hours: return "hr"
                case .minutes: return "min"
                case .seconds: return "sec"
                case .celsius: return "°C"
                case .fahrenheit: return "°F"
                default: return ""
                }
            }
        }

    }
    
    struct MGNote: Decodable {
        var noteText = ""
        var noteType = 0
        
        enum CodingKeys: String, CodingKey {
            case noteText = "NOTE_TEXT"
            case noteType = "TYPE_ID"
        }
        
        enum NoteType: Int, CustomStringConvertible {
            case other = 0
            case chef = 6
            case preparation = 7
            case serving = 8
            case cooking = 10
            
            var description : String {
                switch self {
                case .preparation: return "Preparation"
                case .chef: return "Chef"
                case .cooking: return "Cooking"
                case .serving: return "Serving"
                default: return "Other"
                }
            }
        }

    }
    
    struct MGCategory: Decodable {
        var name: String
       
        enum CodingKeys: String, CodingKey {
            case name = "NAME"
        }
    }
    
    /// Converts MacGourmetImportRecipe to Recipe object
    /// - Parameter imageData: stores Optional Data representing image for this recipe (this conversion will NOT store image with the recipe object due to storing
    /// filename only and needing to have object added to database first; typical use is converting recipe, adding to DB, then saving image using this inout variable after that)
    /// - Parameter categories: stores array of Strings with category names from MacGourmet import; similar to images, this cannot be saved on Recipe object
    /// until after is appended to database, so typical use involves using this value after that (with `addCategoryByName()`)
    /// - Returns: Recipe object with (nearly) matching data from the MacGourmetImport Recipe
    func convertToRecipe(imageData: inout Data?, categories arrCategories: inout [String]?) -> Recipe {
        var recipe = Recipe(
            id: UUID().uuidString,
            name: name,
            createdDate: Date(),
            lastModifiedDate: Date(),
            lastPrepared: nil,
            source: source ?? "",
            sourceDetails: (url?.isEmpty == false ? url : nil) ?? (publicationPage?.isEmpty == false ? publicationPage : nil) ?? "",
            introduction: summary ?? "",
            difficulty: difficulty.map { Difficulty(rawValue: $0) ?? .notSet } ?? .notSet,
            rating: .notSet,
            imageFilename: nil,
            imageThumbnailData: nil,
            isFavorite: false,
            wantToMake: false,
            yield: yield ?? "",
            directions: [],
            ingredients: [],
            notes: [],
            preparationTimes: []
        )
        
        if let image = image {
            imageData = image
        }
        
        if let directions = directions {
            recipe.directions = directions.flatMap { mgDirection in
                var result: [Direction] = []
                
                // If labelText exists and is not empty, create a heading direction
                if let labelText = mgDirection.labelText, !labelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(Direction(
                        id: UUID().uuidString,
                        isHeading: true,
                        text: labelText
                    ))
                }
                
                // Always create the main direction (unless directionText is blank)
                if let directionText = mgDirection.directionText, !directionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(Direction(
                        id: UUID().uuidString,
                        isHeading: false,
                        text: directionText
                    ))
                }
                
                return result
            }
        }
        
        if let ingredients = ingredients {
            recipe.ingredients = ingredients.map { mgIngredient in
                //print("1. \(mgIngredient)")
                let isHeading = mgIngredient.isDivider ?? false
                let isMain = mgIngredient.isMain ?? false
                
                var text = mgIngredient.description ?? ""
                if !isHeading {
                    if let measurement = mgIngredient.measurement, let quantity = mgIngredient.quantity {
                        text = "\(quantity) \(measurement) \(text)".trimmingCharacters(in: .whitespaces)
                    } else if let measurement = mgIngredient.measurement {
                        text = "\(measurement) \(text)".trimmingCharacters(in: .whitespaces)
                    } else if let quantity = mgIngredient.quantity {
                        text = "\(quantity) \(text)".trimmingCharacters(in: .whitespaces)
                    }
                    
                    if let direction = mgIngredient.direction, !direction.isEmpty {
                        text += " (\(direction))"
                    }
                }
                
                let ingredient = Ingredient(
                    id: UUID().uuidString,
                    isHeading: isHeading,
                    isMain: isMain,
                    text: text
                )
                //print("2. \(ingredient)")
                return ingredient
            }
        }
        
        if let notes = notes {
            recipe.notes = notes.map { note in
                let title: String
                if let type = MGNote.NoteType(rawValue: note.noteType) {
                    title = type.description
                } else {
                    title = MGNote.NoteType.other.description
                }
                
                return Note(
                    id: UUID().uuidString,
                    title: title,
                    content: note.noteText
                )
            }
        }
        
        if let prepTimes = prepTimes {
            recipe.preparationTimes = prepTimes.map { prepTime in
                let type: String
                if let timeName = MGPrepTime.TimeType(rawValue: prepTime.timeTypeID)?.description {
                    type = timeName
                } else {
                    type = MGPrepTime.TimeType.other.description
                }
                
                return PreparationTime(
                    id: UUID().uuidString,
                    type: type,
                    timeString: prepTime.timeString
                )
            }
        }
        
        if let categories = categories {
            var cats = [String]()
            categories.forEach { cat in
                if (cat.name != "") {
                    cats.append(cat.name)
                }
            }
            arrCategories = cats
        }
                

        
        // Set servings on the recipe if it's a valid positive number (see if need to check? haven't so far...)
        if let servingsValue = servings, servingsValue > 0 {
            recipe.servings = servingsValue
        }
        
        
        return recipe
    }
}


