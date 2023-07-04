//
//  ShoppingList.swift
//  Salty
//
//  Created by Robert on 7/3/23.
//

import Foundation
import RealmSwift

final class ShoppingList: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var _id: ObjectId
    /// The backlink to the `RecipeLibrary` this item is a part of.
    @Persisted(originProperty: "shoppingLists") var recipeLibrary: LinkingObjects<RecipeLibrary>
    @Persisted var name = ""
    @Persisted var items = List<ShoppingListItem>()
}
