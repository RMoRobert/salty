//
//  RecipeDifficultyView.swift
//  Salty
//
//  Created by Robert on 7/3/23.
//

import SwiftUI

struct RecipeDifficultyView: View {
    @State var difficulty: Recipe.Difficulty
    
    var body: some View {
        //        Text("Difficulty: \(recipe.difficulty.stringValue().localizedCapitalized)")
        Gauge(value: Double(difficulty.rawValue), in: Double(Recipe.Difficulty.easy.rawValue)...Double(Recipe.Difficulty.difficult.rawValue)) {
            Label("Difficulty", systemImage: "checkmark.diamond")
        } currentValueLabel: {
            Text(difficulty.stringValue().capitalized)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: false)
        } minimumValueLabel: {
            Label("Easy", systemImage: "circle.fill")
                .foregroundColor(.green)
        } maximumValueLabel: {
            Label("Difficult", systemImage: "diamond.fill")
                .foregroundColor(.black)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [.green, .green, .yellow, .yellow, .orange, .red, .black]))
    }
    
//    var body: some View {
//        //        Text("Difficulty: \(recipe.difficulty.stringValue().localizedCapitalized)")
//        Gauge(value: Double(difficulty.rawValue), in: Double(Recipe.Difficulty.easy.rawValue)...Double(Recipe.Difficulty.difficult.rawValue)) {
//            Label("Difficulty", systemImage: "checkmark.diamond")
//        } currentValueLabel: {
//            Text(difficulty.stringValue().capitalized)
//                .font(.caption)
//                .fixedSize(horizontal: false, vertical: false)
//        } minimumValueLabel: {
//            Label("Easy", systemImage: "circle.fill")
//                .foregroundColor(.green)
//        } maximumValueLabel: {
//            Label("Difficult", systemImage: "diamond.fill")
//                .foregroundColor(.black)
//        }
//        .gaugeStyle(.accessoryCircular)
//        .tint(Gradient(colors: [.green, .green, .yellow, .yellow, .orange, .red, .black]))
//    }
}

struct RecipeDifficultyView_Previews: PreviewProvider {
    static var previews: some View {
        let difficulty = Recipe.Difficulty.somewhatEasy
        RecipeDifficultyView(difficulty: difficulty)
    }
}
