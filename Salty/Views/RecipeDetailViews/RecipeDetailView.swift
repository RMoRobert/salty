//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 6/20/23.
//

import Foundation
import SwiftUI
import SharingGRDB
import Flow

struct RecipeDetailView: View {
    let recipe: Recipe
    @Environment(\.openWindow) private var openWindow
    @State private var showingFullImage = false

    @State private var courseName: String?
    #if !os(macOS)
    @State private var isTitleVisible: Bool = true
    #else
    @State private var isTitleVisible = false
    #endif
    


    // TODO: Offload to ViewModel at some point:
    @Dependency(\.defaultDatabase) private var database
    
    #if !os(macOS)
    private var shouldShowNavigationTitle: Bool {
        // Show navigation title when the recipe title is no longer visible
        return !isTitleVisible
    }
    #endif
    
    var body: some View {
        ScrollView {
            Group {
                TitleAndBasicInfoSection(recipe: recipe, isTitleVisible: $isTitleVisible, showingFullImage: $showingFullImage, courseName: courseName)
                PrepTimeAndFavoriteEtcSection(recipe: recipe)
                IntroductionSection(recipe: recipe)
                AdaptiveStack(verticalAlignment: .top) {
                    IngredientsSection(recipe: recipe)
                    DirectionsSection(recipe: recipe)
                }
                NotesSection(recipe: recipe)
                    .padding(.top, 2)
                TagsSection(recipe: recipe)
                    .padding(.top, 2)
            }
            .padding()
        }
        .fontDesign(.rounded)
        .background(Color.recipeDetailPageBackgroundColorful)
        .foregroundStyle(Color.recipeDetailBoxForeground)
        .textSelection(.enabled)
        .sheet(isPresented: $showingFullImage) {
            RecipeFullImageView(recipe: recipe)
                .frame(minWidth: 300, idealWidth: 800, minHeight: 450, idealHeight: 900)
        }
        .onAppear {
            loadCourseName()
        }
        .onChange(of: recipe.courseId) { _, _ in
            // I feel like there is a better way to do this, but this works for now...
            loadCourseName()
        }
            #if !os(macOS)
            .navigationTitle(shouldShowNavigationTitle ? recipe.name : "")
            #else
            .navigationTitle(recipe.name)  // do I need this on macOS? Not displayed but doesn't seem to hurt
            #endif
            .toolbarTitleDisplayMode(.inline)
    }

    
    private func loadCourseName() {
        guard let courseId = recipe.courseId else {
            courseName = nil
            return
        }
        
        do {
            let course = try database.read { db in
                try Course.fetchOne(db, id: courseId)
            }
            courseName = course?.name
        } catch {
            courseName = nil
        }
    }

}

// MARK: - Private Subviews

private struct TitleAndBasicInfoSection: View {
    let recipe: Recipe
    @Binding var isTitleVisible: Bool
    @Binding var showingFullImage: Bool
    let courseName: String?
    var body: some View {
        AdaptiveStack {
            VStack(spacing: 4) {
                HStack {
                    Text(recipe.name)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(alignment: .top)
#if !os(macOS)
                        .background(
                            GeometryReader { titleGeometry in
                                Color.clear
                                    .onAppear {
                                        let titleFrame = titleGeometry.frame(in: .global)
                                        let buffer: CGFloat = 90
                                        isTitleVisible = titleFrame.maxY > buffer
                                    }
                                    .onChange(of: titleGeometry.frame(in: .global)) { _, newFrame in
                                        let buffer: CGFloat = 90
                                        isTitleVisible = newFrame.maxY > buffer
                                    }
                                    .accessibilityHidden(true)
                            }
                        )
#endif
                }
                Spacer()
                if !recipe.source.isEmpty {
                    HStack {
                        Image(systemName: "text.book.closed")
                        Text(recipe.source)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Source: \(recipe.source)")
                }
                if !recipe.sourceDetails.trimmingCharacters(in: .whitespaces).isEmpty {
                    let sourceDetails = recipe.sourceDetails.trimmingCharacters(in: .whitespaces)
                    if let url = URL(string: sourceDetails),
                       let scheme = url.scheme?.lowercased().starts(with: "http") {
                        Link(destination: url) {
                            Text(sourceDetails)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .foregroundStyle(Color.blue)
                        }
                    }
                    else {
                        Text(recipe.sourceDetails)
                    }
                }
                Spacer()
                HFlow(itemSpacing: 12) {
                    if let courseName = courseName {
                        HStack {
                            Image(systemName: "fork.knife.circle")
                            Text(courseName)
                        }
                        .modifier(CapsuleBackgroundModifier())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Course: \(courseName)")
                    }
                    if !recipe.yield.isEmpty {
                        HStack {
                            Image(systemName: "circle.grid.2x2")
                            Text(recipe.yield)
                        }
                        .modifier(CapsuleBackgroundModifier())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Yield: \(recipe.yield)")
                    }
                    if let servings = recipe.servings, servings > 0 {
                        HStack {
                            Image(systemName: "person.2")
                            Text(servings.description)
                        }
                        .modifier(CapsuleBackgroundModifier())
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
        .padding([.top], 8)
        .modifier(RecipeSectionBoxModifier())
    }
}

private struct PrepTimeAndFavoriteEtcSection: View {
    let recipe: Recipe
    var body: some View {
        VStack {
            if (recipe.isFavorite || recipe.wantToMake) {
                HFlow(itemSpacing: 24, rowSpacing: 12) {
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
            if recipe.preparationTimes.count > 0 {
                HFlow(itemSpacing: 12, rowSpacing: 8) {
                    ForEach(recipe.preparationTimes) { prepTime in
                        HStack {
                            Image(systemName: "clock")
                            VStack {
                                Text("\(prepTime.type)")
                                    .font(.caption)
                                Text("\(prepTime.timeString)")
                            }
                            .accessibilityHidden(true)
                        }
                        .modifier(CapsuleBackgroundModifier())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Preparation time: type: \(prepTime.type), duration: \(prepTime.timeString)")
                    }
                }
                .padding(.horizontal)
            }
            HFlow(alignment: .top, itemSpacing: 60, rowSpacing: 30) {
                VStack(spacing: 10) {
                    RatingView(recipe: recipe, showLabel: false)
                }
                VStack(spacing: 10) {
                    DifficultyView(recipe: recipe, showLabel: false)
                }
            }
        }
        .padding(8)
        .modifier(RecipeSectionBoxModifier())
    }
}

private struct IntroductionSection: View {
    let recipe: Recipe
    var body: some View {
        if !recipe.introduction.isEmpty {
            VStack {
                Text(recipe.introduction)
                    .italic()
                    .padding()
            }
        }
        else {
            VStack {}
                .padding(1)
        }
    }
}

private struct IngredientsSection: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ingredients")
                .modifier(TitleStyle())
            ForEach(recipe.ingredients.indices, id: \.self) { index in
                let isHeading = recipe.ingredients[index].isHeading
                if isHeading {
                    Text(recipe.ingredients[index].text)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.recipeDetailBoxForeground2)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            //.baselineOffset(1)
                            .foregroundStyle(.recipeDetailBoxForeground)
                            .fontWeight(.bold)
                        Text(recipe.ingredients[index].text)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.recipeDetailBoxForeground)
                            .fontWeight(.regular)
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(minWidth: 85, maxWidth: 300)
        .modifier(RecipeSectionBoxModifier())
    }
}

private struct DirectionsSection: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Directions")
                .modifier(TitleStyle())
            ForEach(recipe.directions.indices, id: \.self) { index in
                let isHeading = recipe.directions[index].isHeading ?? false
                if isHeading {
                    Text(recipe.directions[index].text)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.recipeDetailBoxForeground2)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(recipe.directions.prefix(index + 1).filter { $0.isHeading != true }.count).")
                            .fontWeight(.semibold)
                        Text(recipe.directions[index].text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(minWidth: 95, maxWidth: 1000)
        .modifier(RecipeSectionBoxModifier())
    }
}

private struct NotesSection: View {
    let recipe: Recipe
    var body: some View {
        if recipe.notes.count > 0 {
            VStack(alignment: .leading) {
                Text("Notes")
                    .modifier(TitleStyle())
                    .padding(.bottom, 2) // override to reduce space below heading
                ForEach(recipe.notes.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.notes[index].title)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.recipeDetailBoxForeground2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(recipe.notes[index].content)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, index == 0 ? 0 : 2) // no top padding for first note
                    .padding(.bottom, 2)
                }
            }
            
            .modifier(RecipeSectionBoxModifier())
            .frame(maxWidth: .infinity)
        }
    }
}

private struct TagsSection: View {
    let recipe: Recipe
    var body: some View {
        if recipe.tags.count > 0 {
            VStack(alignment: .leading) {
                Text("Tags")
                    .modifier(TitleStyle())
                HFlow(itemSpacing: 8, rowSpacing: 16) {
                    ForEach(recipe.sortedTags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Color.recipeDetailPageBackgroundColorful.opacity(0.66), in: Capsule())
                    }
                }
            }
            .modifier(RecipeSectionBoxModifier())
            .frame(maxWidth: .infinity)
        }
    }
}


// MARK: Modifier Structs

private struct TitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title2)
            .fontWeight(.bold)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }
}

private struct IconShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(radius: 0.5, x:0.5, y:1)
    }
}

private struct CapsuleBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
            .background(Color.recipeDetailPageBackgroundColorful.opacity(0.66))
            .clipShape(Capsule())
            .padding(EdgeInsets(top: 1, leading: 4, bottom: 10, trailing: 6))
    }
}


private struct RecipeSectionBoxModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .background(Color.recipeDetailBoxBackground)
            .foregroundStyle(Color.recipeDetailBoxForeground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.recipeDetailBoxShadow.opacity(0.7), radius: 4, x:1, y:1)
            .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    }
}



#Preview {
    RecipeDetailView(recipe: SampleData.sampleRecipes[0])
}


