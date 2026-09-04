//
//  RecipeListDropIndicator.swift
//  Salty
//
//  The line drawn between rows while a row is being dragged over the ingredient or direction editor.
//

import SwiftUI

/// Marks where a dragged row would land: always immediately above the row that drew it.
struct RecipeListDropIndicator: View {
    let isActive: Bool

    var body: some View {
        if isActive {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
}
