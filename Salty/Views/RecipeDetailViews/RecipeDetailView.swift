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

struct RecipeDetailViewOLD: View {
    let recipe: Recipe
    @Environment(\.openWindow) private var openWindow
    @State private var showingFullImage = false

    @State private var courseName: String?
    #if !os(macOS)
    @State private var isTitleVisible: Bool = true
    #endif

    // TODO: Offload to ViewModel at some point:
    @Dependency(\.defaultDatabase) private var database
    
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #else
    enum UserInterfaceSizeClass {
        case compact
        case regular
    }
    let horizontalSizeClass = UserInterfaceSizeClass.regular
    #endif
    
    #if !os(macOS)
    private var shouldShowNavigationTitle: Bool {
        // Show navigation title when the recipe title is no longer visible
        return !isTitleVisible
    }
    #endif
    
    var body: some View {
        ScrollView {
            Section {
                AdaptiveStack {
                    VStack(spacing: 4) {
                        HStack {
                            Text(recipe.name)
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                                                    #if !os(macOS)
                                    .background(
                                        GeometryReader { titleGeometry in
                                            Color.clear
                                                .onAppear {
                                                    // Check if title is visible in the viewport with buffer
                                                    let titleFrame = titleGeometry.frame(in: .global)
                                                    let buffer: CGFloat = 90 // Show nav title when title is 90pt from top
                                                    isTitleVisible = titleFrame.maxY > buffer
                                                }
                                                .onChange(of: titleGeometry.frame(in: .global)) { _, newFrame in
                                                    // Update visibility when title position changes with buffer
                                                    // Update visibility when title position changes with buffer
                                                    let buffer: CGFloat = 90 // Show nav title when title is 90pt from top
                                                    isTitleVisible = newFrame.maxY > buffer
                                                }
                                                .accessibilityHidden(true)
                                        }
                                    )
                                    #endif
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
                        if !recipe.sourceDetails.trimmingCharacters(in: .whitespaces).isEmpty {
                            let sourceDetails = recipe.sourceDetails.trimmingCharacters(in: .whitespaces)
                            if let url = URL(string: sourceDetails), 
                               let scheme = url.scheme?.lowercased().starts(with: "http") {
                                Link(destination: url) {
                                    Text(sourceDetails)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                }
                            }
                            else {
                                Text(recipe.sourceDetails)
                            }
                        }
                        HFlow(itemSpacing: 12) {
                            if let courseName = courseName {
                                HStack {
                                    Image(systemName: "fork.knife.circle")
                                    //.modifier(IconShadowModifier())
                                    Text(courseName)
                                }
                                .modifier(CapsuleBackgroundModifier())
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Course: \(courseName)")
                            }
                            if !recipe.yield.isEmpty {
                                HStack {
                                    Image(systemName: "circle.grid.2x2")
                                    //.modifier(IconShadowModifier())
                                    Text(recipe.yield)
                                }
                                .modifier(CapsuleBackgroundModifier())
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Yield: \(recipe.yield)")
                            }
                            if let servings = recipe.servings, servings > 0 {
                                HStack {
                                    Image(systemName: "person.2")
                                    //.modifier(IconShadowModifier())
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
                if recipe.preparationTimes.count > 0 {
                    HFlow(itemSpacing: 12, rowSpacing: 8) {
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
                            .modifier(CapsuleBackgroundModifier())
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Preparation time: type: \(prepTime.type), duration: \(prepTime.timeString)")
                        }
                    }
                    .padding(.horizontal)
                }
                
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
                
                HFlow(alignment: .top, itemSpacing: 60, rowSpacing: 30) {
                    VStack(spacing: 10) {
                        //Text("Rating:")
                        RatingView(recipe: recipe, showLabel: false)
                    }
                    VStack(spacing: 10) {
                        //Text("Difficulty:")
                        DifficultyView(recipe: recipe, showLabel: false)
                    }
                }
                .padding()
                
                if !recipe.introduction.isEmpty {
                    VStack {
                        Text(recipe.introduction)
                    }
                    .padding([.leading, .trailing])
                }
                
                AdaptiveStack {
                    VStack(alignment: .leading) {
                        Text("Ingredients")
                            .modifier(TitleStyle())
                        ForEach(recipe.ingredients.indices, id: \.self) { index in
                            Text((recipe.ingredients[index].isHeading ? "" : "• ") + recipe.ingredients[index].text)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(recipe.ingredients[index].isHeading ? .callout : .none)
                                .fontWeight(recipe.ingredients[index].isHeading ? .semibold : .regular)
                                .padding(.bottom, 1)
                        }
                    }
                    .frame(minWidth: 100, maxWidth: 400)
                    .padding()
                    
                    VStack(alignment: .leading) {
                        Text("Directions")
                            .modifier(TitleStyle())
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
                    .frame(minWidth: 100, maxWidth: 400)
                    .padding()
                }
                
                if (recipe.notes.count > 0) {
                    VStack(alignment: .leading) {
                        Text("Notes")
                            .modifier(TitleStyle())
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
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                }
                
                if (recipe.tags.count > 0) {
                    VStack(alignment: .leading) {
                        Text("Tags")
                            .modifier(TitleStyle())
                        HFlow(itemSpacing: 8, rowSpacing: 16) {
                            ForEach(recipe.sortedTags, id: \.self) { tag in
                                Label(tag, systemImage: "tag")
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .background(.thinMaterial, in: Capsule())
                            }
                        }
                    }
                    .padding()
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
    
    struct TitleStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom)
        }
    }
    
    struct IconShadowModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .shadow(radius: 0.5, x:0.5, y:1)
        }
    }
    
    struct CapsuleBackgroundModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(EdgeInsets(top: 1, leading: 4, bottom: 10, trailing: 6))
        }
    }
    
}


#Preview {
    RecipeDetailViewOLD(recipe: SampleData.sampleRecipes[0])
}


