//
//  Ingredient.swift
//  Salty
//
//  Created by Robert on 4/19/23.
//

import Foundation
import RealmSwift

final class Ingredient: EmbeddedObject, ObjectKeyIdentifiable {
    //@Persisted(primaryKey: true) var _id: ObjectId
    @Persisted var isCategory = false
    @Persisted var name = ""
    @Persisted var quantity = ""
    @Persisted var notes = ""
    @Persisted var isMain = false
    
    func toString() -> String {
        return "\(quantity) \(name) \(notes)"
    }
}
