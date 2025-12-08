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
    @State private var showingHelp = false
    @State private var textContent: String = ""
    @State private var hasChanges: Bool = false
    @AppStorage("monospacedBulkEditFont") private var monospacedBulkEditFont = false
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Ingredients")
                    .fontWeight(.semibold)
                
                TextEditor(text: $textContent)
                    .border(Color.secondary.opacity(0.50))
                    .font(monospacedBulkEditFont ? .system(.body, design: .monospaced) : .body)
                    .onChange(of: textContent) { _, _ in
                        hasChanges = true
                    }
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .padding([.trailing])
                    
                    Button("Clean Up") {
                        cleanUpText()
                    }
                    .disabled(textContent.isEmpty)
                    .padding([.leading, .trailing])
                    
                    Button("Help", systemImage: "questionmark.circle") {
                        showingHelp = true
                    }
                    .padding([.trailing])
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .alert("How to Use Editor", isPresented: $showingHelp) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Each line represents one ingredient (or heading). Add a blank line before any lines that are to be interpreted as headings, or end those lines with a colon. Ingredient lines ending with \"[*]\" (no quotes) will be marked as main ingredients. Select \"Clean Up\" to remove common list delimiter characters and trim whitespace.")
                    }
                    
                    
                    Spacer()
                    
                    Button("Save") {
                        saveIngredients()
                        dismiss()
                    }
                    .padding([.leading])
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges)
                }
            }
            .padding()
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
            .onAppear {
                loadIngredients()
            }
        }
    }
    
    private func loadIngredients() {
        textContent = IngredientTextParser.formatIngredients(recipe.ingredients)
        hasChanges = false
    }
    
    private func saveIngredients() {
        recipe.ingredients = IngredientTextParser.parseIngredients(from: textContent)
        hasChanges = false
    }
    
    private func cleanUpText() {
        textContent = IngredientTextParser.cleanUpText(textContent)
        hasChanges = true
    }
}

#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    RecipeIngredientsBulkEditView(recipe: $recipe)
}
