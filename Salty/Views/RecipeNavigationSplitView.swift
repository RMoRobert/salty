//
//  RecipeNavigationSplitView.swift
//  Salty
//
//  Created by Robert on 10/25/22.
//

import SwiftUI
import RealmSwift

struct RecipeNavigationSplitView: View {
    @ObservedRealmObject var recipeLibrary: RecipeLibrary
    @Environment(\.openWindow) private var openWindow
    @State private var searchString = ""
    @State private var selectedSidebarItemId: RealmSwift.ObjectId?
    @State private var selectedRecipeIDs = Set<RealmSwift.ObjectId>()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showEditRecipeView = false
    @State private var showingEditLibCategoriesSheet = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedSidebarItemId) {
                Section("Library") {
                    Label("All Recipes", systemImage: "book")
                        .tag(recipeLibrary._id)
                }
                Section("Categories") {
                    ForEach(recipeLibrary.categories.sorted(byKeyPath: "name")) { category in
                        Label(category.name, systemImage: "doc.plaintext")
                            .tag(category._id)
                    }
                    //                        Button("Edit") {
                    //                            showingEditLibCategoriesSheet = true
                    //                        }
                    //                        .frame(alignment: .trailing)
                    //                        .buttonStyle(.plain)
                    //                        .font(.footnote)
                    //                        .sheet(isPresented: $showingEditLibCategoriesSheet) {
                    //                            LibraryCategoriesEditView()
                    //                                .presentationDetents([.large])
                    //                        }
                }
                Section("Smart Lists") {
                    //ForEach(recipeLibrary.smartLists.sorted(byKeyPath: "name")) { smartList in
                    Label("Coming Soon!", systemImage: "doc.text.magnifyingglass")
                    //}
                }
                Section("Shopping Lists") {
                    ForEach(recipeLibrary.shoppingLists.sorted(byKeyPath: "name")) { shoppingList in
                        Label(shoppingList.name, systemImage: "list.bullet.rectangle")
                            .tag(shoppingList._id)
                    }
                }
                .contextMenu {
                    Button(role: .destructive, action: {
                        addNewShoppingist()
                    }) {
                        Text("New List")
                    }
                }
            }
            //.listStyle(.sidebar)
        }
    content: {
        if let sidebarItemId = selectedSidebarItemId {
            if sidebarItemId == recipeLibrary._id {
                let recipesToList = (searchString == "") ? AnyRealmCollection(recipeLibrary.recipes) : AnyRealmCollection(recipeLibrary.recipes.where({ $0.name.contains(searchString, options: [.caseInsensitive, .diacriticInsensitive]) }))
                ScrollViewReader { scrollProxy in
                    List(selection: $selectedRecipeIDs) {
                        ForEach (recipesToList.sorted(byKeyPath: "name"), id: \._id) { recipe in
                            NavigationLink(value: recipe) {
                                RecipeRowView(recipe:  recipe)
                            }
                            .contextMenu {
                                Button(role: .destructive, action: deleteSelectedRecipes) {
                                    Text("Delete")
                                }
                                .keyboardShortcut(.delete, modifiers: [.command])
                            }
                        }
                        .onDelete(perform: $recipeLibrary.recipes.remove)
                        .onMove(perform: $recipeLibrary.recipes.move)
                    }
                    .navigationTitle("Recipes")
                    .toolbar {
                        Button(role: .destructive, action: deleteSelectedRecipes) {
                            Label("Delete Recipe", systemImage: "minus")
                        }
                        Button(action: {
                            let newRecipe = Recipe()
                            $recipeLibrary.recipes.append(newRecipe)
                            selectedRecipeIDs.removeAll()
                            selectedRecipeIDs.insert(newRecipe._id)
                            withAnimation {
                                // TODO: Why is this not working?
                                scrollProxy.scrollTo(newRecipe._id)
                            }
                        }) {
                            Label("New Recipe", systemImage: "plus")
                        }
                        Button(action: {
                            openWindow(id: "import-page")
                        }) {
                            Label("Import", systemImage: "square.and.arrow.down.on.square")
                        }
                    }
                    .searchable(text: $searchString)
                }
            }
            else if let selectedCategory = recipeLibrary.categories.first(where: { $0._id == sidebarItemId }) {
                // TODO: Clean up, can share some code w/ above?
                List(selection: $selectedRecipeIDs) {
                    ForEach (selectedCategory.recipes, id: \._id) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeRowView(recipe:  recipe)
                        }
                        .contextMenu {
                            Button(role: .destructive, action: deleteSelectedRecipes) {
                                Text("Delete")
                            }
                            .keyboardShortcut(.delete, modifiers: [.command])
                        }
                    }
                    .onDelete(perform: $recipeLibrary.recipes.remove)
                    .onMove(perform: $recipeLibrary.recipes.move)
                }
                .navigationTitle("Recipes")
                .toolbar {
                    Button(role: .destructive, action: deleteSelectedRecipes) {
                        Label("Delete Recipe", systemImage: "minus")
                    }
                    Button(action: {
                        $recipeLibrary.recipes.append(Recipe())
                    }) {
                        Label("New Recipe", systemImage: "plus")
                    }
                }
            }
            else {
                Text("something else selected?")
            }
        }
        else {
            Text("No category/list selected")
                .foregroundStyle(.tertiary)
        }
    }
    detail: {
        // TODO: better multiple selection? (show stack?)
        VStack {
            //            if let selectedRecipe = selectedRecipes.first  {
            if let selectedRecipe = recipeLibrary.recipes.first(where: { $0._id == selectedRecipeIDs.first })  {
                if !self.showEditRecipeView {
                    RecipeDetailView(recipe: selectedRecipe)
                    //RecipeDetailHTMLView(recipe: selectedRecipe)
                        .toolbar {
                            Button("Edit") {
                                self.showEditRecipeView = true
                            }
                        }
                }
                else {
                    RecipeDetailEditView(recipe: selectedRecipe)
                        .toolbar {
                            Button("End Edit") {
                                self.showEditRecipeView = false
                            }
                        }
                }
            }
            else {
                Text("No recipe selected")
                    .foregroundStyle(.tertiary)
                    .font(.title)
            }
        }
    }
    .navigationTitle("Recipes")
    }
    
    func deleteSelectedRecipes() -> () {
        // TODO: there has to be a better way?
        let ids = selectedRecipeIDs.map { $0 }
        ids.forEach { theId in
            if let theIdx = recipeLibrary.recipes.firstIndex(where: {
                $0._id == theId
            }) {
                $recipeLibrary.recipes.remove(at: theIdx)
            }
        }
    }
    
    func addNewShoppingist() -> () {
        let sl = ShoppingList()
        sl.name = "New Shopping List"
        $recipeLibrary.shoppingLists.append(sl)
    }
}

struct RecipeNavigationSplitView_Preview: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let lib = realm.objects(RecipeLibrary.self)        
        RecipeNavigationSplitView(recipeLibrary: lib.first!)
    }
}
