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
    @State private var showingEditSheet = false
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
                                .multilineTextAlignment(.center)
                        }
                        if !recipe.source.isEmpty {
                            HStack {
                                Image(systemName: "text.book.closed")
                                    //.modifier(IconShadowModifier())
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
                        HStack(spacing: 15) {
                            if !recipe.yield.isEmpty {
                                HStack {
                                    Image(systemName: "circle.grid.2x2")
                                        //.modifier(IconShadowModifier())
                                    Text(recipe.yield)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Yield: \(recipe.yield)")
                            }
                            if let servings = recipe.servings, servings > 0 {
                                HStack {
                                    Image(systemName: "person.2")
                                        //.modifier(IconShadowModifier())
                                    Text(servings.description)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Servings: \(servings)")
                            }
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
                                    //.modifier(IconShadowModifier())
                                VStack {
                                    Text("\(prepTime.type)")
                                        .font(.caption)
                                    Text("\(prepTime.timeString)")
                                }
                                .accessibilityHidden(true)
                            }
                            .padding(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(EdgeInsets(top: 1, leading: 4, bottom: 10, trailing: 6))
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
                                .modifier(IconShadowModifier())
                            Text("Favorite")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Marked as Favorite")
                    }
                    if (recipe.wantToMake) {
                        HStack {
                            Image(systemName: "checkmark.diamond")
                                .foregroundColor(Color.green.opacity(0.8))
                                .modifier(IconShadowModifier())
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
                
                HOrVStack(alignFirstTextLeadingIfHStack: true, spacingIfHStack: 60, spacingIfVStack: 30) {
                    VStack(spacing: 10) {
                        Text("Rating:")
                        RatingView(recipe: recipe, showLabel: true)
                    }
                    VStack(spacing: 10) {
                        Text("Difficulty:")
                        DifficultyView(recipe: recipe, showLabel: true)
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
                        ForEach(recipe.directions.indices, id: \.self) { index in
                            HStack(alignment: .top) {
                                if recipe.directions[index].isHeading != true {
                                    Text("\(recipe.directions.prefix(index + 1).filter { $0.isHeading != true }.count).")
                                        .fontWeight(.semibold)
                                } else {
                                    Spacer()
                                        .frame(width: 20)
                                }
                                if recipe.directions[index].isHeading == true {
                                    Text(recipe.directions[index].text)
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                } else {
                                    Text(recipe.directions[index].text)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.bottom, 2)
                                }
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
                .frame(minWidth: 300, idealWidth: 800, minHeight: 450, idealHeight: 900)
        }
        .sheet(isPresented: $showingEditSheet) {
            #if os(macOS)
            RecipeDetailEditDesktopView(recipe: recipe, isNewRecipe: false)
                .frame(minWidth: 600, minHeight: 500)
            #else
            NavigationStack {
                RecipeDetailEditMobileView(recipe: recipe, isNewRecipe: false)
            }
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingEditSheet = true
                }) {
                    Label("Edit", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}

struct IconShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(radius: 0.5, x:0.5, y:1)
    }
}

struct NoModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(radius: 0.5, x:0.5, y:1)
    }
}


#Preview {
    RecipeDetailView(recipe: SampleData.sampleRecipes[2])
}
