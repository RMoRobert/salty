//
//  DifficultyView.swift
//  Salty
//
//  Created by Robert on 7/3/23.
//

import SharingGRDB
import SwiftUI

struct DifficultyView: View {
    let recipe: Recipe
    
    var body: some View {
        if recipe.difficulty == .notSet {
            Gauge(value: 0, in: 0...0) {
                Label("Difficulty", systemImage: "checkmark.diamond")
            } currentValueLabel: {
                Text("Not Set")
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
            .scaleEffect(1.2)
            
        }
        
        else {
            Gauge(value: Double(recipe.difficulty.rawValue), in: Double(Difficulty.easy.rawValue)...Double(Difficulty.difficult.rawValue)) {
                Label("Difficulty", systemImage: "checkmark.diamond")
            } currentValueLabel: {
                Text(recipe.difficulty.stringValue().capitalized)
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
            .scaleEffect(1.2)
        }
    }
}

//struct DifficultyView_Previews: PreviewProvider {
//    static var previews: some View {
//        let recipe = try! prepareDependencies {
//            $0.defaultDatabase = try Salty.appDatabase()
//            return try $0.defaultDatabase.read { db in
//                try Recipe.all.fetchOne(db)!
//            }
//        }
//        DifficultyView(recipe: $recipe)
//    }
//}
//    
    
