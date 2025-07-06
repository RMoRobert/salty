//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 10/21/22.
//

import SwiftUI
import SharingGRDB

struct RecipeDetailEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @Environment(\.dismiss) var dismiss
    @State var recipe: Recipe
    @State private var showingEditCategoriesSheet = false
    @State private var showingEditIngredientsSheet = false
    @State private var showingEditDirectionsSheet = false
    @State private var showingEditPreparationTimes = false
    @State private var showingEditNotesSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Basic Information Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Basic Information")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.bottom, 4)
                    
                    Form {
                        TextField("Name:", text: $recipe.name)
                        TextField("Source:", text: $recipe.source)
                        TextField("Source Details:", text: $recipe.sourceDetails)
                        TextField("Yield:", text: $recipe.yield)
                    }
                    
                    VStack {
                        // Rating and Difficulty in a row
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Rating:")
                                    .frame(width: 80, alignment: .leading)
                                RatingEditView(recipe: $recipe)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Difficulty:")
                                    .frame(width: 80, alignment: .leading)
                                DifficultyEditView(recipe: $recipe)
                            }
                            VStack(alignment: .leading) {
                                Text("Categories:")
                                Button("Edit Categories") {
                                    showingEditCategoriesSheet.toggle()
                                }
                            }
                            .buttonStyle(.bordered)
                            .popover(isPresented: $showingEditCategoriesSheet) {
                                CategoryEditView(recipe: $recipe)
                            }
                        }
                        
                        VStack {
                            Text("Image:")
                            RecipeImageEditView(recipe: $recipe, imageFrameSize: 100)
                        }
                        
                        HOrVStack() {
                            Toggle("Is favorite?", isOn: $recipe.isFavorite)
                            Toggle("Want to make", isOn: $recipe.wantToMake)
                        }
                    }
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Introduction Section 
                VStack(alignment: .leading, spacing: 16) {
                    Text("Introduction")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.bottom, 4)
                    
                    VStack(spacing: 12) {
                        TextField("Introduction", text: $recipe.introduction, axis: .vertical)
                            .lineLimit(5...10)
                    }
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Directions Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Directions")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Edit Directions") {
                            showingEditDirectionsSheet.toggle()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if recipe.directions.isEmpty {
                        Text("No directions added")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(recipe.directions.enumerated()), id: \.element.id) { index, direction in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1).")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, alignment: .leading)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let stepName = direction.stepName, !stepName.isEmpty {
                                            Text(stepName)
                                                .font(.callout)
                                                .fontWeight(.semibold)
                                        }
                                        Text(direction.text)
                                            .font(.body)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .popover(isPresented: $showingEditDirectionsSheet) {
                    DirectionsEditView(recipe: $recipe)
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Ingredients Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Ingredients")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Edit Ingredients") {
                            showingEditIngredientsSheet.toggle()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if recipe.ingredients.isEmpty {
                        Text("No ingredients added")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recipe.ingredients) { ingredient in
                                if ingredient.isHeading {
                                    Text(ingredient.text)
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                        //.padding(.top, 8)
                                } else {
                                    Text(ingredient.text)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }
                .popover(isPresented: $showingEditIngredientsSheet) {
                    IngredientsEditView(recipe: $recipe)
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Preparation Times Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Preparation Times")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Edit Times") {
                            showingEditPreparationTimes.toggle()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if recipe.preparationTimes.isEmpty {
                        Text("No preparation times added")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recipe.preparationTimes) { preparationTime in
                                Label("\(preparationTime.type): \(preparationTime.timeString)", systemImage: "clock")
                            }
                        }
                    }
                }
                .popover(isPresented: $showingEditPreparationTimes) {
                    PreparationTimesEditView(recipe: $recipe)
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Notes Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Notes")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Edit Notes") {
                            showingEditNotesSheet.toggle()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if recipe.notes.isEmpty {
                        Text("No notes added")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(recipe.notes) { note in
                                VStack(alignment: .leading, spacing: 4) {
                                    if !note.title.isEmpty {
                                        Text(note.title)
                                            .fontWeight(.semibold)
                                    }
                                    Text(note.content)
                                        .font(.body)
                                        .lineLimit(6)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .popover(isPresented: $showingEditNotesSheet) {
                    NotesEditView(recipe: $recipe)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.secondary)
                
                Button("Save") {
                    recipe.lastModifiedDate = Date()
                    try? database.write { db in
                        try Recipe.upsert(Recipe.Draft(recipe))
                        .execute(db)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
        }
    }
}

// Custom view for consistent label and text field layout
struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var axis: Axis = .horizontal
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                //.font(.subheadline)
                //.fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
                .accessibilityHidden(true)
            
            TextField(label, text: $text, axis: axis)
                //.textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }
}

#Preview {
    RecipeDetailEditView(recipe: SampleData.sampleRecipes[0])
}
