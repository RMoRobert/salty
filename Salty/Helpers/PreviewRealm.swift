//
//  PreviewRealm.swift
//  Salty
//
//  Created by Robert on 5/30/23.
//

import Foundation
import RealmSwift

extension RecipeLibrary {
    static var previewRealm: Realm {
        var realm: Realm
        let identifier = "saltyPreviewRealm"
        let config = Realm.Configuration(inMemoryIdentifier: identifier)
        do {
            realm = try Realm(configuration: config)
            let realmObjects = realm.objects(RecipeLibrary.self)
            if realmObjects.count == 1 {
                return realm
            } else {
                try realm.write {
                    let cat1 = Category()
                    cat1.name = "Breads"
                    let cat2 = Category()
                    cat2.name = "Soups"
                    
                    let r = Recipe()
                    r.name = "New Recipe"
                    r.difficulty = .easy
                    r.rating = .three
                    r.introduction = "This is a recipe I used to make"
                    r.source = "Karen"
                    r.sourceDetails = "allrecipes.com/123"
                    r.yield = "2 dozen"
                    
                    let ing1 = Ingredient()
                    ing1.name = "flour"; ing1.quantity = "1 cup"; ing1.notes = "sifted"; ing1.isMain = true
                    let ing2 = Ingredient()
                    ing2.name = "water"; ing2.quantity = "2 Tbl"
                    let ing3 = Ingredient()
                    ing3.name = "For dusting"; ing3.isCategory = true
                    let ing4 = Ingredient()
                    ing4.name = "flour"; ing4.quantity = "pinch"; ing4.notes = "for dusting"
                    r.ingredients.append(objectsIn: [ing1, ing2, ing3])
                    
                    let dir1 = Direction()
                    dir1.text = "Mix all main ingredients well."
                    let dir2 = Direction()
                    dir2.text = "Set aside for 15 minutes. Lorem ipsum dolor sit amet. This is some longer text. Do other things while you are waiting. Then, return to the next step. Brown fox, lazy dog, etc. Now you're ready!"
                    let dir3 = Direction()
                    dir3.text = "Dust with flour if needed."
                    dir3.stepName = "Dusting"
                    r.directions.append(objectsIn: [dir1, dir2, dir3])
                    
                    let pt1 = PreparationTime()
                    pt1.name = "Cooking"
                    pt1.timeString = "45 minutes"
                    let pt2 = PreparationTime()
                    pt2.name = "Ready In"
                    pt2.timeString = "1.5 hours"
                    r.preparationTimes.append(objectsIn: [pt1, pt2])
                    
                    let n1 = Note()
                    n1.name = "Serving"
                    n1.text = "You can also pair this with X or Y to get Z. More text here. Lorem ispum dolor sit amet. Long note text for seeing what happend when the line goes longer. Abra cadabra!"
                    r.notes.append(objectsIn: [n1])
                    
                    let recLib = RecipeLibrary()
                    recLib.recipes.append(r)
                    recLib.categories.append(objectsIn: [cat1, cat2])
                    realm.add(recLib)
                }
                return realm
            }
        } catch let error {
            fatalError("Can't bootstrap item data: \(error.localizedDescription)")
        }
    }
}
