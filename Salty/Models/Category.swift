//
//  Category.swift
//  Salty
//
//  Created by Robert on 5/19/23.
//

import Foundation
import RealmSwift

final class Category: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    @Persisted var name: String
    @Persisted(originProperty: "categories") var recipes: LinkingObjects<Recipe>
}

extension Category {
    static func getDefaultCategoryNames() -> [String] {
        return [
            "Main Course",
            "Side Dish",
            "Dessert",
            "Appetizer",
            "Meat",
            "Vegetarian"
        ]
    }
}
