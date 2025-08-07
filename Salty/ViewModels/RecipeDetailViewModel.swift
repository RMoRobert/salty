//
//  RecipeDetailViewModel.swift
//  Salty
//
//  Created by Robert on 8/6/25.
//

import Foundation
import OSLog
import SharingGRDB

@Observable
@MainActor
class RecipeDetailViewModel {
    private let logger = Logger(subsystem: "Salty", category: "App")
    
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    
    // MARK: - State
    let recipe: Recipe
    var courseName: String?
    var showingFullImage = false
    
    #if !os(macOS)
    var isTitleVisible: Bool = true
    #else
    var isTitleVisible = false
    #endif
    
    // MARK: - Computed Properties
    #if !os(macOS)
    var shouldShowNavigationTitle: Bool {
        // Show navigation title when the recipe title is no longer visible
        return !isTitleVisible
    }
    #endif
    
    // MARK: - Initialization
    init(recipe: Recipe) {
        self.recipe = recipe
        loadCourseName()
    }
    
    // MARK: - Public Methods
    func loadCourseName() {
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
            logger.error("Error loading course name: \(error)")
            courseName = nil
        }
    }
    
    func showFullImage() {
        showingFullImage = true
    }
    
    func hideFullImage() {
        showingFullImage = false
    }
}
