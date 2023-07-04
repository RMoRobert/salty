//
//  ShoppingListItem.swift
//  Salty
//
//  Created by Robert on 7/3/23.
//

import Foundation
import RealmSwift

final class ShoppingListItem: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var _id: ObjectId
    /// The backlink to the `ShoppingList` this item is a part of.
    @Persisted(originProperty: "items") var recipeLibrary: LinkingObjects<ShoppingList>
    @Persisted var name = ""
    @Persisted var notes = ""
}
