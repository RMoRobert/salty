//
//  PreviewHelpers.swift
//  Salty
//
//  Created by Assistant on 12/19/24.
//

import Foundation
import SharingGRDB
import SwiftUICore

// Helper function to safely prepare dependencies for previews
func prepareDependenciesIfNeeded() {
    do {
        try prepareDependencies {
            $0.defaultDatabase = try Salty.appDatabase()
        }
    } catch {
        // Dependencies already prepared, ignore the error
        print("Dependencies already prepared: \(error)")
    }
}

// MARK: - Preview Environment Keys

private struct PreviewDataKey: EnvironmentKey {
    static let defaultValue: (recipes: [Recipe], categories: [Category])? = nil
}

extension EnvironmentValues {
    var previewData: (recipes: [Recipe], categories: [Category])? {
        get { self[PreviewDataKey.self] }
        set { self[PreviewDataKey.self] = newValue }
    }
}

//// MARK: - Preview Helper Functions
//
///// Creates a sample recipe for previews without database dependencies
//func createSampleRecipe() -> Recipe {
//    SampleData.createMainSampleRecipe()
//}
//
///// Creates a sample recipe with minimal data for simple previews
//func createMinimalSampleRecipe() -> Recipe {
//    SampleData.createMinimalSampleRecipe()
//}
//
///// Creates a sample recipe with complex data for testing edge cases
//func createComplexSampleRecipe() -> Recipe {
//    SampleData.createComplexSampleRecipe()
//} 
