//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 6/20/23.
//

import Foundation
import SwiftUI
import SharingGRDB

struct RecipeDetailView: View {
    let recipe: Recipe
    @Environment(\.openWindow) private var openWindow
    @State private var showingFullImage = false
    //@State private var showingEditSheet = false
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #else
    enum UserInterfaceSizeClass {
        case compact
        case regular
    }
    let horizontalSizeClass = UserInterfaceSizeClass.regular
    #endif
    
    var body: some View {
        ScrollView {
            Section {
                HOrVStack {
                    VStack(spacing: 4) {
                        HStack {
                            Text(recipe.name)
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        if !recipe.source.isEmpty {
                            HStack {
                                Image(systemName: "text.book.closed")
                                Text(recipe.source)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Source: \(recipe.source)")
                        }
                        if !recipe.sourceDetails.isEmpty {
                            if let url = URL(string: recipe.sourceDetails) {
                                Link(recipe.sourceDetails, destination: url)
                            }
                            else {
                                Text(recipe.sourceDetails)
                            }
                        }
                        if !recipe.yield.isEmpty {
                            HStack {
                                Image(systemName: "person.2")
                                Text(recipe.yield)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Yield: \(recipe.yield)")
                        }
                    }
                    .padding()
                    if recipe.imageFilename != nil {
                        RecipeImageView(recipe: recipe)
                            .padding()
                            .onTapGesture {
                                showingFullImage = true
                            }
                    }
                }
                if recipe.preparationTimes.count > 0 {
                    HOrVStack {
                        ForEach(recipe.preparationTimes) { prepTime in
                            HStack {
                                Image(systemName: "clock")
                                Text("\(prepTime.type): \(prepTime.timeString)")
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Preparation time: type: \(prepTime.type), duration: \(prepTime.timeString)")
                        }
                    }
                    .padding(.horizontal)
                }
                
                if (recipe.isFavorite || recipe.wantToMake) {
                    HOrVStack {
                    if (recipe.isFavorite) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                            Text("Favorite")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Marked as Favorite")
                    }
                    if (recipe.wantToMake) {
                        HStack {
                            Image(systemName: "checkmark.diamond")
                                .foregroundColor(Color.green.opacity(0.8))
                            Text("Want to Make")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Marked as Want to Make")
                    }
                }
                    .padding(.horizontal)
                    .opacity((recipe.isFavorite || recipe.wantToMake) ? 1 : 0)
                    .allowsHitTesting(recipe.isFavorite || recipe.wantToMake)
            }
                
                HOrVStack(alignFirstTextLeadingIfHStack: true) {
                    VStack {
                        Text("Rating:")
                        if recipe.rating != .notSet {
                            RatingView(recipe: recipe).padding()
                        }
                        else {
                            Text("(not set)")
                                .foregroundColor(.secondary)
                        }
                    }
                    VStack {
                        Text("Difficulty:")
                        DifficultyView(recipe: recipe).padding()
                    }
                }
                .padding()
                
                if !recipe.introduction.isEmpty {
                    VStack {
                        Text(recipe.introduction)
                    }
                    .padding([.leading, .trailing])
                }
                HOrVStack(alignFirstTextLeadingIfHStack: true) {
                    VStack(alignment: .leading) {
                        Text("Ingredients")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.bottom)
                        ForEach(recipe.ingredients.indices, id: \.self) { index in
                            Text(recipe.ingredients[index].text)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(recipe.ingredients[index].isHeading ? .callout : .none)
                                .fontWeight(recipe.ingredients[index].isHeading ? .semibold : .regular)
                                .padding(.bottom, 2)
                        }
                    }
                    .padding()
                    .frame(minWidth: 100, maxWidth: .infinity)
                    VStack(alignment: .leading) {
                        Text("Directions")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.bottom)
                        // TODO: Align step name with text, not number (i.e., farther right)?
                        ForEach(recipe.directions.indices, id: \.self) { index in
                            if (recipe.directions[index].stepName != nil && recipe.directions[index].stepName != "") {
                                Text(recipe.directions[index].stepName!)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                            }
                            HStack(alignment: .top) {
                                Text("\(index+1).")
                                    .fontWeight(.semibold)
                                Text(recipe.directions[index].text)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 2)
                            }
                        }
                    }
                    .padding()
                    .frame(minWidth: 100, maxWidth: .infinity)
                }
                if (recipe.notes.count > 0) {
                VStack(alignment: .leading) {
                    Text("Notes")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.bottom)
                    ForEach(recipe.notes.indices, id: \.self) { index in
                        Text(recipe.notes[index].title)
                            .font(.callout)
                            .fontWeight(.bold)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(recipe.notes[index].content)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .frame(minWidth: 100, maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $showingFullImage) {
            RecipeFullImageView(recipe: recipe)
                .frame(minWidth: 400, minHeight: 400)
        }
//        .toolbar {
//            ToolbarItem {
//                Button(action: {
//                    showingEditSheet = true
//                }) {
//                    Label("Edit Recipe", systemImage: "info.circle")
//                }
//                .keyboardShortcut("e", modifiers: .command)
//            }
//        }
//        .sheet(isPresented: $showingEditSheet) {
//            RecipeDetailEditView(recipe: recipe)
//                .frame(minWidth: 600, minHeight: 500)
//        }
    }
}


#Preview {
    RecipeDetailView(recipe: SampleData.sampleRecipes[0])
}
