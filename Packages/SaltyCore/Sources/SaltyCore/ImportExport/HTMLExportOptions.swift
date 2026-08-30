//
//  HTMLExportOptions.swift
//  Salty
//
//  Created by Robert on 1/20/25.
//

import Foundation

public struct HTMLExportOptions {
    public var includeIntroduction: Bool = true
    public var includeIngredients: Bool = true
    public var includeDirections: Bool = true
    public var includeNotes: Bool = true
    public var includeVariations: Bool = true
    public var includePreparationTimes: Bool = true
    public var includeRating: Bool = true
    public var includeDifficulty: Bool = true
    public var includeImage: Bool = true

    public init(
        includeIntroduction: Bool = true,
        includeIngredients: Bool = true,
        includeDirections: Bool = true,
        includeNotes: Bool = true,
        includeVariations: Bool = true,
        includePreparationTimes: Bool = true,
        includeRating: Bool = true,
        includeDifficulty: Bool = true,
        includeImage: Bool = true
    ) {
        self.includeIntroduction = includeIntroduction
        self.includeIngredients = includeIngredients
        self.includeDirections = includeDirections
        self.includeNotes = includeNotes
        self.includeVariations = includeVariations
        self.includePreparationTimes = includePreparationTimes
        self.includeRating = includeRating
        self.includeDifficulty = includeDifficulty
        self.includeImage = includeImage
    }
}

