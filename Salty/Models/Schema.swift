//
//  Schema.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SharingGRDB
import OSLog
import Foundation

private let logger = Logger(subsystem: "Salty", category: "Database")

// Record Types

@Table("recipe")
struct Recipe: Codable, Hashable, Identifiable, Equatable  {
    var id: String
    var name: String = ""
    var createdDate: Date = Date()
    var lastModifiedDate: Date = Date()
    var lastPrepared: Date?
    var source: String = ""
    var sourceDetails: String = ""
    var introduction: String = ""
    var difficulty: Difficulty = .notSet
    var rating: Rating = .notSet
    var imageData: Data?
    var isFavorite: Bool = false
    var wantToMake: Bool = false
    var yield: String = ""
    @Column(as: [Direction].JSONRepresentation.self)
    var directions: [Direction] = []
    @Column(as: [Ingredient].JSONRepresentation.self)
    var ingredients: [Ingredient] = []
    @Column(as: [Note].JSONRepresentation.self)
    var notes: [Note] = []
    @Column(as: [PreparationTime].JSONRepresentation.self)
    var preparationTimes: [PreparationTime] = []
    
    var summary: String {
        return (
            introduction != "" ? introduction : (
                source != "" ? source : (
                    sourceDetails != "" ? sourceDetails : ""
                )
            )
        )
    }
    
    //    var categories: [Category]?
    //    var tags: [Tag]?
}

extension Recipe: FetchableRecord, PersistableRecord, DatabaseValueConvertible {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let createdDate = Column(CodingKeys.createdDate)
        static let lastModifedDate = Column(CodingKeys.lastModifiedDate)
        static let lastPrepared = Column(CodingKeys.lastPrepared)
        static let source = Column(CodingKeys.source)
        static let sourceDetails = Column(CodingKeys.sourceDetails)
        static let introduction = Column(CodingKeys.introduction)
        static let difficulty = Column(CodingKeys.difficulty)
        static let rating = Column(CodingKeys.rating)
        static let imageData = Column(CodingKeys.imageData)
        static let isFavorite = Column(CodingKeys.isFavorite)
        static let wantToMake = Column(CodingKeys.wantToMake)
        static let directions = JSONColumn(CodingKeys.directions)
        static let ingredients = JSONColumn(CodingKeys.ingredients)
        static let notes  = JSONColumn(CodingKeys.notes)
        static let preparationTimes = JSONColumn(CodingKeys.preparationTimes)
    }
    
    static var databaseSelection: [any SQLSelectable] {
        [Columns.id, Columns.name, Columns.createdDate, Columns.lastModifedDate,
         Columns.source, Columns.sourceDetails, Columns.introduction,
         Columns.difficulty, Columns.rating, Columns.imageData,
         Columns.lastPrepared, Columns.isFavorite, Columns.wantToMake,
         Database.json(Columns.directions), Database.json(Columns.ingredients),
         Database.json(Columns.notes), Database.json(Columns.preparationTimes)]
    }
}

@Selection
struct RecipeSummary: Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    let createdDate: Date
    let lastModifiedDate: Date
    let lastPrepared: Date?
    let source: String
    let sourceDetails: String
    let introduction: String
    let difficulty: Difficulty
    let rating: Rating
    let imageData: Data?
    let isFavorite: Bool
}


struct Note: Codable, Hashable, Equatable, Identifiable {
    var id: String
    var title: String
    var content: String
}

@Table("course")
struct Course: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
}

extension Course: FetchableRecord, PersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
    }
    
    static var databaseSelection: [any SQLSelectable] {
        [Columns.id, Columns.name]
    }
}

struct Direction: Codable, Hashable, Equatable, Identifiable  {
    var id: String
    var stepName: String?
    var text: String
}

struct Ingredient: Codable, Hashable, Equatable, Identifiable  {
    var id: String
    var isHeading: Bool = false
    var isMain: Bool = false
    var text: String
}

struct PreparationTime: Codable, Hashable, Equatable, Identifiable  {
    var id: String
    var type: String
    var timeString: String
}

@Table("category")
struct Category: Hashable, Identifiable, Codable, Equatable {
    var id: String
    var name: String
}

extension Category: FetchableRecord, PersistableRecord  {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        
        static let recipes = hasMany(Recipe.self)
    }
    
    static var databaseSelection: [any SQLSelectable] {
        [Columns.id, Columns.name]
    }
}

@Table("tag")
struct Tag: Hashable, Identifiable, Codable, Equatable  {
    var id: String
    var name: String
}

extension Tag: FetchableRecord, PersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
    }
    
    static var databaseSelection: [any SQLSelectable] {
        [Columns.id, Columns.name]
    }
}

enum Difficulty: Int, Codable, CaseIterable, QueryBindable {
    case notSet = 0,  easy, somewhatEasy, medium, slightlyDifficult, difficult
    
    // for use with SwiftUI sliders:
    init(index: Double = 0) {
        if let type = Self.allCases.first(where: { $0.asIndex == index }) {
            self = type
        } else {
            self = .notSet
        }
    }
    var asIndex: Double {
        return Double(self.rawValue)
    }
    
    var id:  Int {
        return self.rawValue
    }
    
    func stringValue() -> String {
        switch(self) {
        case .notSet:
            return "(not set)"
        case .easy:
            return "easy"
        case .somewhatEasy:
            return "somewhat easy"
        case .medium:
            return "medium"
        case .slightlyDifficult:
            return "slightly difficult"
        case .difficult:
            return "difficult"
        }
    }
    
}

enum Rating: Int, CaseIterable, Identifiable, Codable, QueryBindable {
    case notSet = 0, one, two, three, four, five
    
    // for use with SwiftUI sliders:
    init(index: Double = 0) {
        if let type = Self.allCases.first(where: { $0.asIndex == index }) {
            self = type
        } else {
            self = .notSet
        }
    }
    
    var id: Int {
        return self.rawValue
    }
    
    var asIndex: Double {
        return Double(self.rawValue)
    }
    
    func stringValue() -> String {
        switch(self) {
        case .notSet:
            return "not set"
        case .one:
            return "1"
        case .two:
            return "2"
        case .three:
            return "3"
        case .four:
            return "4"
        case .five:
            return "5"
        }
    }
}


// Junction tables

@Table("recipeCourse")
struct RecipeCourse:  Codable, Hashable, Equatable, PersistableRecord, FetchableRecord {
    var recipeId: String
    var courseId: String
    
    enum Columns {
        static let recipeId = Column(CodingKeys.recipeId)
        static let courseId = Column(CodingKeys.courseId)
    }
    
    static var databaseSelection: [any SQLSelectable] {
        [Columns.recipeId, Columns.courseId]
    }
}

@Table("recipeCategory")
struct RecipeCategory:  Codable, Hashable, Equatable, PersistableRecord, FetchableRecord {
    var recipeId: String
    var categoryId: String
    
    enum Columns {
        static let recipeId = Column(CodingKeys.recipeId)
        static let categoryId = Column(CodingKeys.categoryId)
    }
    
    static var databaseSelection: [any SQLSelectable] {
        [Columns.recipeId, Columns.categoryId]
    }
}

@Table("recipeTag")
struct RecipeTag: Codable, Hashable, Equatable, PersistableRecord, FetchableRecord {
    var recipeId: String
    var tagId: String
    
    enum Columns {
        static let recipeId = Column(CodingKeys.recipeId)
        static let tagId = Column(CodingKeys.tagId)
    }
    
    static var databaseSelection: [any SQLSelectable] {
        [Columns.recipeId, Columns.tagId]
    }
}


// DatabaseWriter code, migrations, etc:

func appDatabase() throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    let database: any DatabaseWriter
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    configuration.prepareDatabase { db in
#if DEBUG
        db.trace(options: .profile) {
            if context == .live {
                logger.debug("\($0.expandedDescription)")
            } else {
                print("\($0.expandedDescription)")
            }
        }
#endif
    }
    if context == .preview {
        database = try DatabaseQueue(configuration: configuration)
    } else {
        let path =
         context == .live
        ? URL.documentsDirectory.appending(component: "saltyLibrary.sqlite").path()
        : URL.temporaryDirectory.appending(component: "\(UUID().uuidString)-saltyLibrary.sqlite").path()
        logger.info("open \(path)")
        database = try DatabasePool(path: path, configuration: configuration)
    }
    var migrator = DatabaseMigrator()
#if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
#endif
    migrator.registerMigration("Create initial tables") { db in
        try db.create(table: "recipe") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("createdDate", .datetime)
            t.column("lastModifiedDate", .datetime)
            t.column("lastPrepared", .datetime)
            t.column("source", .text)
            t.column("sourceDetails", .text)
            t.column("introduction", .text)
            t.column("difficulty", .integer)
            t.column("rating", .integer)
            t.column("imageData", .blob)
            t.column("isFavorite", .boolean)
            t.column("wantToMake", .boolean)
            t.column("yield", .text)
            t.column("directions", .jsonText)
            t.column("ingredients", .jsonText)
            t.column("notes", .jsonText)
            t.column("preparationTimes", .jsonText)
        }
        try db.create(table: "course") { t in
            t.primaryKey("id", .text)
            t.column("name", .text)
        }
        try db.create(table: "category") { t in
            t.primaryKey("id", .text)
            t.column("name", .text)
        }
        try db.create(table: "tag") { t in
            t.primaryKey("id", .text)
            t.column("name", .text)
        }
        try db.create(table: "recipeCourse") { t in
            t.column("recipeId", .text).notNull().indexed().references("recipe", onDelete: .cascade)
            t.column("courseId", .text).notNull().indexed().references("course", onDelete: .cascade)
            t.primaryKey(["recipeId", "courseId"])
        }
        try db.create(table: "recipeCategory") { t in
            t.column("recipeId", .text).notNull().indexed().references("recipe", onDelete: .cascade)
            t.column("categoryId", .text).notNull().indexed().references("category", onDelete: .cascade)
            t.primaryKey(["recipeId", "categoryId"])
        }
        try db.create(table: "recipeTag") { t in
            t.column("recipeId", .text).notNull().indexed().references("recipe", onDelete: .cascade)
            t.column("tagId", .text).notNull().indexed().references("tag", onDelete: .cascade)
            t.primaryKey(["recipeId", "tagId"])
        }
    }
    try migrator.migrate(database)
    if context == .preview {
      try database.write { db in
        try db.seedSampleData()
      }
    }
    return database
}

#if DEBUG
extension Database {
    func seedSampleData() throws {
        try seed {
            // Add sample categories
            Category(id: UUID().uuidString, name: "Breakfast")
            Category(id: UUID().uuidString, name: "Lunch")
            Category(id: UUID().uuidString, name: "Dinner")
            Category(id: UUID().uuidString, name: "Dessert")
            
            Course(id: UUID().uuidString, name: "Main")
            Course(id: UUID().uuidString, name: "Dessert")
            
            Tag(id: UUID().uuidString, name: "easy")
            Tag(id: UUID().uuidString, name: "vegan")
            
            Recipe(
                id: UUID().uuidString,
                name: "My Recipe",
                createdDate: Date(),
                lastModifiedDate: Date(),
                lastPrepared: Date(timeIntervalSinceNow: 0-60*24*45),
                source: "Some Book",
                introduction: "This is an introduction for my recipe. Some introductions are long, so let's make this one long, too. Here is some more text. Is it long enough yet? Let's write more just in case. Yay, recipes!",
                difficulty: .somewhatEasy,
                rating: Rating.four,
                imageData: nil,
                isFavorite: false,
                wantToMake: false,
                yield: "2 dozen",
                directions: [
                    Direction(id: UUID().uuidString, text: "Do the first step. We'll make this text a bit longer so there is a chance that it will need to wrap or show other text rendering nuances. Lorem ipsum dolor sit amet consectetur adipisicing elit. Quo, molestias! Quasi, voluptatem. Now, let's move on to the  next step -- but not before adding a bit more here just in case. Wow, what a long step!"),
                    Direction(id: UUID().uuidString, text: "Now, do the second step."),
                ],
                ingredients: [
                    Ingredient(id: UUID().uuidString, isMain: true, text: "1 cup flour"),
                    Ingredient(id: UUID().uuidString, text: "1/2 cup water"),
                    Ingredient(id: UUID().uuidString, text: "salt, to taste")
                ],
                notes: [
                    Note(id: UUID().uuidString, title: "Note 1", content: "This is the text of the note")
                ],
                preparationTimes: [
                    PreparationTime(id: UUID().uuidString, type: "Preparation", timeString: "25 Minutes")
                ]
            )
        }
    }
}
#endif
