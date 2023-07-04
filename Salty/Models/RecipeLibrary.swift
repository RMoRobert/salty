//
//  RecipeLibrary.swift
//  Salty
//
//  Created by Robert on 5/19/23.
//

import Foundation
import RealmSwift

final class RecipeLibrary: Object, ObjectKeyIdentifiable {
    /// The unique ID of the RecipeLibrary. `primaryKey: true` declares the
    /// _id member as the primary key to the realm.
    @Persisted(primaryKey: true) var _id: ObjectId

    /// The collection of Items in this group.
    @Persisted var recipes = List<Recipe>()
    @Persisted var categories = List<Category>()
    @Persisted var shoppingLists = List<ShoppingList>()
}
