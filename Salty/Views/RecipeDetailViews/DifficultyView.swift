//
//  DifficultyView.swift
//  Salty
//
//  Created by Robert on 7/3/23.
//

import SQLiteData
import SwiftUI

struct DifficultyView: View {
    let recipe: Recipe
    let showLabel: Bool
    let barWidth: CGFloat
    let barHeight: CGFloat
    
    init(recipe: Recipe, showLabel: Bool = true, barWidth: CGFloat = 120, barHeight: CGFloat = 12) {
        self.recipe = recipe
        self.showLabel = showLabel
        self.barWidth = barWidth
        self.barHeight = barHeight
    }
    
    private var difficultyPosition: CGFloat {
        if recipe.difficulty == .notSet {
            return 0
        }
        
        // Map difficulty values (1-5) to position (0-1)
        let minValue = Double(Difficulty.easy.rawValue)  // 1
        let maxValue = Double(Difficulty.difficult.rawValue)  // 5
        let currentValue = Double(recipe.difficulty.rawValue)
        
        return CGFloat((currentValue - minValue) / (maxValue - minValue))
    }
    
    private var markerColor: Color {
        switch recipe.difficulty {
        case .notSet:
            return .gray
        case .easy:
            return .green
        case .somewhatEasy:
            return .green
        case .medium:
            return .yellow
        case .slightlyDifficult:
            return .orange
        case .difficult:
            return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Optional text label above the bar
            if showLabel {
                Text(recipe.difficulty == .notSet ? "(not set)" : recipe.difficulty.stringValue().capitalized)
                    .font(.caption)
                    //.fontWeight(.medium)
                    .foregroundColor(recipe.difficulty == .notSet ? .secondary : .primary)
            }
            
            // Difficulty bar
            ZStack(alignment: .leading) {
                // Background gradient bar
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth, height: barHeight)
                    .cornerRadius(barHeight / 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .stroke(.thinMaterial, lineWidth: 1)
                    )
                    .opacity(recipe.difficulty == .notSet ? 0.50 : 1)
                
                // Difficulty marker (triangle or question mark)
                let markerSize = barHeight * 1.33
                if recipe.difficulty == .notSet {
                    // Question mark for not set
                    Text("?")
                        .font(.system(size: markerSize * 0.8, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: markerSize, height: markerSize)
                        .background(
                            Circle()
                                .fill(.white)
                                .stroke(.thickMaterial, lineWidth: 2)
                        )
                        .offset(x: 0.5 * (barWidth - markerSize), y: 0)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                } else {
                    // Triangle for set difficulties
                    Triangle()
                        .fill(markerColor)
                        .stroke(.ultraThickMaterial, lineWidth: 2)
                        .frame(width: markerSize, height: markerSize)
                        .offset(x: difficultyPosition * (barWidth - markerSize), y: 0-barHeight/2.5)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                }
            }
            
            // Optional min/max labels
            HStack {
                Text("Easy")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Difficult")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: barWidth)
        }
        .accessibilityLabel("Recipe difficulty: \(recipe.difficulty.stringValue())")
    }
}

// MARK: - Triangle Shape
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start at the bottom point
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        // Draw to top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        // Draw to top-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Close the path back to the bottom point
        path.closeSubpath()
        
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        DifficultyView(recipe: SampleData.sampleRecipes[1], showLabel: true)
        DifficultyView(recipe: SampleData.sampleRecipes[0], showLabel: false)
        
        // Different sizes
        DifficultyView(recipe: SampleData.sampleRecipes[2], barWidth: 150, barHeight: 10)
        DifficultyView(recipe: SampleData.sampleRecipes[1], barWidth: 250, barHeight: 16)
    }
    .padding()
}
