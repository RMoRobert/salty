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
        var lines: [String] = []
        
        for direction in recipe.directions {
            if direction.isHeading == true {
                // Add double blank line before heading
                lines.append("")
                lines.append("")
                lines.append(direction.text)
            } else {
                lines.append(direction.text)
            }
        }
        
        textContent = lines.joined(separator: "\n")
        hasChanges = false
    }
    
    private func saveDirections() {
        let lines = textContent.components(separatedBy: .newlines)
        var newDirections: [Direction] = []
        
        var i = 0
        while i < lines.count {
            var line = lines[i].trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty {
                // Skip empty lines
                i += 1
                continue
            }
            
            // Check if this line is preceded by two blank lines, making it a heading:
            let isHeadingByDoubleLine = i > 1 && 
                lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty && 
                lines[i - 2].trimmingCharacters(in: .whitespaces).isEmpty
            // Check if this line ends with a colon, making it a heading using the alternate format:
            let isHeadingByColon = line.hasSuffix(":")
            if isHeadingByColon {
                // strip colon for cleanliness
                line = String(line.dropLast())
            }
            let isHeading = isHeadingByDoubleLine || isHeadingByColon
            
            let direction = Direction(
                id: UUID().uuidString,
                isHeading: isHeading,
                text: line
            )
            
            newDirections.append(direction)
            i += 1
        }
        
        recipe.directions = newDirections
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
    RecipeDirectionsBulkEditView(recipe: $recipe)
}
