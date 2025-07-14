//
//  RecipeDirectionsBulkEditView.swift
//  Salty
//
//  Created by Robert on 7/13/25.
//

import SwiftUI

struct RecipeDirectionsBulkEditView: View {
    @Binding var recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @State private var showingHelp = false
    @State private var textContent: String = ""
    @State private var hasChanges: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Directions")
                    .font(.title2)
                    .fontWeight(.semibold)
                
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
                    
                    Button("Help", systemImage: "questionmark.circle") {
                        showingHelp = true
                    }
                    .labelStyle(.iconOnly)
                    .alert("How to Use Editor", isPresented: $showingHelp) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Edit directions as plain text. Each line represents one direction step. Single blank lines separate directions. Use double blank lines before any lines that are to be interpreted as section headings, or end those lines with a colon. Select \"Clean Up\" to remove list delimiters and trim whitespace.")
                    }
                    
                    
                    Spacer()
                    
                    Button("Save") {
                        saveDirections()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges)
                }
            }
            .padding()
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
            .onAppear {
                loadDirections()
            }
        }
    }
    
    private func loadDirections() {
        textContent = DirectionTextParser.formatDirections(recipe.directions)
        hasChanges = false
    }
    
    private func saveDirections() {
        recipe.directions = DirectionTextParser.parseDirections(from: textContent)
        hasChanges = false
    }
    
    private func cleanUpText() {
        textContent = DirectionTextParser.cleanUpText(textContent)
        hasChanges = true
    }
}

#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    RecipeDirectionsBulkEditView(recipe: $recipe)
}
