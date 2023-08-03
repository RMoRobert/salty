//
//  LibraryCategoriesEditView.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//

import Foundation
import SwiftUI
import RealmSwift

struct LibraryCategoriesEditView: View {
    @ObservedResults(RecipeLibrary.self) var recipeLibraries
    @State private var selectedCategoryIDs = Set<RealmSwift.ObjectId>()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        if let recipeLibrary = recipeLibraries.first  {
            @ObservedRealmObject var recipeLibrary = recipeLibrary

        }
        else {
            Text("No recipe library found")
        }
    }
    
    func deleteSelectedCategories() -> () {
        let ids = selectedCategoryIDs.map { $0 }
        guard let recipeLibrary = recipeLibraries.first else {
            print("No recipe library found")
            return
        }
        let realm = recipeLibrary.realm!.thaw()
        try! realm.write {
            ids.forEach { theId in
                if let theCat = realm.objects(Category.self).first(where: {
                    $0._id == theId
                }) {
                    realm.delete(theCat)
                }
            }
        }
    }
    
    func deleteCategory(id: RealmSwift.ObjectId) -> () {
        guard let recipeLibrary = recipeLibraries.first else {
            print("No recipe library found")
            return
        }
        let realm = recipeLibrary.realm!.thaw()
        try! realm.write {
            if let theCat = realm.objects(Category.self).first(where: {
                $0._id == id
            }) {
                realm.delete(theCat)
            }
        }
    }
}

struct LibraryCategoryEditView: View {
    @ObservedRealmObject var category: Category
    var body: some View {
        VStack {
            TextField("Name", text: $category.name)
        }
        .padding()
    }
}

struct LibraryCategoriesEditView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LibraryCategoriesEditView()
        }
    }
}

