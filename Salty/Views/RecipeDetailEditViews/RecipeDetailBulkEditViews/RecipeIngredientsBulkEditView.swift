//
//  RecipeIngredientsBulkEditView.swift
//  Salty
//
//  Created by Robert on 7/12/25.
//

import SwiftUI

struct RecipeIngredientsBulkEditView: View {
    @Binding var recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @State private var textContent: String = ""
    @State private var hasChanges: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Ingredients")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Edit ingredients as plain text. Each line represents one ingredient. Add a blank line before any lines that are to be interpreted as headings. Select \"Clean Up\" to remove list delimiters and trim whitespace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $textContent)
                    .border(Color.secondary.opacity(0.50))
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: textContent) { _, _ in
                        hasChanges = true
                    }
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Clean Up") {
                        cleanUpText()
                    }
                    .buttonStyle(.bordered)
                    .disabled(textContent.isEmpty)
                    
                    Spacer()
                    
                    Button("Save") {
                        saveIngredients()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges)
                }
            }
            .padding()
            .frame(minWidth: 500, minHeight: 400)
            .onAppear {
                loadIngredients()
            }
        }
    }
    
    private func loadIngredients() {
        var lines: [String] = []
        
        for ingredient in recipe.ingredients {
            if ingredient.isHeading {
                // Add blank line before heading
                lines.append("")
                lines.append(ingredient.text)
            } else {
                lines.append(ingredient.text)
            }
        }
        
        textContent = lines.joined(separator: "\n")
        hasChanges = false
    }
    
    private func saveIngredients() {
        let lines = textContent.components(separatedBy: .newlines)
        var newIngredients: [Ingredient] = []
        var isMainPreservation: [String: Bool] = [:]
        
        // Create a mapping of existing ingredient text to isMain value for preservation
        for ingredient in recipe.ingredients {
            isMainPreservation[ingredient.text] = ingredient.isMain
        }
        
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty {
                // Skip empty lines
                i += 1
                continue
            }
            
            // Check if this line is followed by a blank line, making it a heading
            let isHeading = i > 0 && lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty
            
            let ingredient = Ingredient(
                id: UUID().uuidString,
                isHeading: isHeading,
                isMain: isMainPreservation[line] ?? false, // Preserve isMain if possible
                text: line
            )
            
            newIngredients.append(ingredient)
            i += 1
        }
        
        recipe.ingredients = newIngredients
        hasChanges = false
    }
    
    private func cleanUpText() {
        let lines = textContent.components(separatedBy: .newlines)
        let cleanedLines = lines.map { line in
            var cleanedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Remove common list markers from the beginning
            let markers = ["*", "-", "•", "○", "▪", "▫", "‣", "⁃"]
            for marker in markers {
                if cleanedLine.hasPrefix(marker) {
                    cleanedLine = String(cleanedLine.dropFirst(marker.count))
                    break
                }
            }
            return cleanedLine.trimmingCharacters(in: .whitespaces)
        }
        textContent = cleanedLines.joined(separator: "\n")
        hasChanges = true
    }
}

#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    RecipeIngredientsBulkEditView(recipe: $recipe)
}
