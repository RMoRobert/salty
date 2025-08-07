//
//  ScanTextForRecipeView.swift
//  Salty
//
//  Created by Robert on 7/13/25.
//

import SwiftUI
import PhotosUI

#if os(iOS)
import VisionKit
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(macOS)
let targetSectionPickerTitle: String = "Target Section:"
#else
let targetSectionPickerTitle: String = "Target Section"
#endif

struct ScanTextForRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var viewModel: RecipeDetailEditViewModel
    @StateObject private var ocrService = RecipeOCRService()
    @State private var selectedImage: CGImage?
    #if os(iOS)
    @State private var multiPageScan: VNDocumentCameraScan?
    #elseif os(macOS)
    @State private var multiPageImages: [CGImage] = []
    #endif
    @State private var showingImagePicker = false
    @State private var showingDocumentScanner = false
    @State private var showingCamera = false
    @State private var showingFilePicker = false
    @State private var targetSection: RecipeDetailEditViewModel.ScanTextTarget
    
    init(viewModel: Binding<RecipeDetailEditViewModel>, initialTarget: RecipeDetailEditViewModel.ScanTextTarget = .ingredients) {
        self._viewModel = viewModel
        self._targetSection = State(initialValue: initialTarget)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Target selection
                VStack {
                    Text("Insert scanned text into:")
                        .padding(.top)
                    Picker(targetSectionPickerTitle, selection: $targetSection) {
                        ForEach(RecipeDetailEditViewModel.ScanTextTarget.allCases, id: \.self) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.horizontal)
                
                // Image selection area
                VStack {
                    if let image = selectedImage {
                        #if os(iOS)
                        Image(uiImage: UIImage(cgImage: image))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        #elseif os(macOS)
                        Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        #endif
                        
                        if ocrService.extractedText.isEmpty {
                            Group {
                                Text("Image added!")
                                    .fontWeight(.semibold)
                                Text("Select \"Extract Text\" to scan for text, then \"Insert Text\" to add it to your \(targetSection.rawValue.lowercased()).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    } else {
                        ContentUnavailableView {
                            Label("No Image", systemImage: "photo")
                        } description: {
                            #if os(macOS)
                            Text("Choose an image to scan for text.")
                            #else
                            Text("Choose or capture an image to scan for text.")
                            #endif
                        }
                    }
                }
                .padding(.horizontal)
                
                // Image source buttons
                HStack(spacing: 12) {
                    #if !os(macOS)
                    Button("Camera") {
                        showingCamera = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Document Scanner") {
                        showingDocumentScanner = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Photo Library") {
                        showingImagePicker = true
                    }
                    .buttonStyle(.bordered)
                    #else
                    Button("Choose File") {
                        showingFilePicker = true
                    }
                    .buttonStyle(.bordered)
                    #endif
                }
                .padding(.horizontal)
                
                // OCR results
                if !ocrService.extractedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Extracted Text:")
                            .font(.headline)
                        
                        TextEditor(text: $ocrService.extractedText)
                            .frame(maxHeight: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)
                }
                
                // Error display
                if let error = ocrService.error {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                }
                
                // Action buttons
                HStack(spacing: 16) {
                    #if os(macOS)
                    Button("Cancel") {
                        dismiss()
                    }
                    #endif
                    Button("Extract Text") {
                        #if os(iOS)
                        if let multiPageScan = multiPageScan {
                            Task {
                                await ocrService.extractTextFromMultiPageScan(multiPageScan)
                            }
                        } else if let image = selectedImage {
                            Task {
                                await ocrService.extractText(from: image)
                            }
                        }
                        #elseif os(macOS)
                        if !multiPageImages.isEmpty {
                            Task {
                                await ocrService.extractTextFromMultiPageScan(multiPageImages)
                            }
                        } else if let image = selectedImage {
                            Task {
                                await ocrService.extractText(from: image)
                            }
                        }
                        #endif
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedImage == nil || ocrService.isProcessing)
                    
                    Button("Insert Text") {
                        insertScannedText()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ocrService.extractedText.isEmpty)
                }
                .padding(.horizontal)
                .padding([.top, .bottom], 8)
            }
            .navigationTitle("Scan Text")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            #endif
        }
        #if !os(macOS)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showingDocumentScanner) {
            DocumentScanner(selectedImage: $selectedImage, multiPageScan: $multiPageScan)
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(selectedImage: $selectedImage)
        }
        #else
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadImageFromSecureURL(url)
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
        #endif
    }
    
    private func insertScannedText() {
        let scannedText = ocrService.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch targetSection {
        case .introduction:
            // Add scanned text to existing introduction
            if !scannedText.isEmpty {
                if viewModel.recipe.introduction.isEmpty {
                    viewModel.recipe.introduction = scannedText
                } else {
                    viewModel.recipe.introduction += "\n\n" + scannedText
                }
            }
        case .ingredients:
            // Parse scanned text as ingredients using lenient parsing
            let ingredients = parseIngredientsFromText(scannedText)
            for ingredient in ingredients {
                viewModel.recipe.ingredients.append(ingredient)
            }
        case .directions:
            // Parse scanned text as directions using lenient parsing
            let directions = parseDirectionsFromText(scannedText)
            for direction in directions {
                viewModel.recipe.directions.append(direction)
            }
        }
        
        dismiss()
    }
    
    // MARK: - Lenient Parsing for Section-Specific Scanning
    // adjusted from whole-document scanner
    
    private func parseIngredientsFromText(_ text: String) -> [Ingredient] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var ingredients: [Ingredient] = []
        
        for line in lines {
            // Skip obvious non-ingredient lines
            if isObviousNonIngredient(line) {
                continue
            }
            
            // Clean the ingredient text
            let cleanedText = cleanIngredientText(line)
            
            // Only add if we have meaningful content
            if cleanedText.count >= 2 {
                ingredients.append(Ingredient(
                    id: UUID().uuidString,
                    isHeading: false,
                    isMain: false,
                    text: cleanedText
                ))
            }
        }
        
        return ingredients
    }
    
    private func parseDirectionsFromText(_ text: String) -> [Direction] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var directions: [Direction] = []
        var currentDirection = ""
        
        for line in lines {
            // Skip obvious non-direction lines
            if isObviousNonDirection(line) {
                continue
            }
            
            // Check if this line starts a new step
            if isDirectionStep(line) {
                // Save the previous direction if we have one
                if !currentDirection.isEmpty {
                    let cleanedText = cleanDirectionText(currentDirection)
                    if cleanedText.count >= 5 {
                        directions.append(Direction(
                            id: UUID().uuidString,
                            isHeading: false,
                            text: cleanedText
                        ))
                    }
                }
                
                // Start a new direction
                currentDirection = line
            } else {
                // Continue the current direction
                if !currentDirection.isEmpty {
                    currentDirection += " " + line
                } else {
                    // This might be a direction without a step number
                    currentDirection = line
                }
            }
        }
        
        // Add the last direction if we have one
        if !currentDirection.isEmpty {
            let cleanedText = cleanDirectionText(currentDirection)
            if cleanedText.count >= 5 {
                directions.append(Direction(
                    id: UUID().uuidString,
                    isHeading: false,
                    text: cleanedText
                ))
            }
        }
        
        return directions
    }
    
    private func isObviousNonIngredient(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        
        // Skip section headers
        let sectionHeaders = ["ingredients", "directions", "instructions", "method", "steps", "preparation", "cooking", "notes", "tips", "variations"]
        if sectionHeaders.contains(where: { lowercased.contains($0) }) {
            return true
        }
        
        // Skip metadata lines
        let metadataPatterns = ["prep time", "cook time", "total time", "servings", "yield", "makes", "serves"]
        if metadataPatterns.contains(where: { lowercased.contains($0) }) {
            return true
        }
        
        // Skip very short lines that are likely not ingredients
        if line.count < 2 {
            return true
        }
        
        return false
    }
    
    private func isObviousNonDirection(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        
        // Skip section headers
        let sectionHeaders = ["ingredients", "directions", "instructions", "method", "steps", "preparation", "cooking", "notes", "tips", "variations"]
        if sectionHeaders.contains(where: { lowercased.contains($0) }) {
            return true
        }
        
        // Skip metadata lines
        let metadataPatterns = ["prep time", "cook time", "total time", "servings", "yield", "makes", "serves"]
        if metadataPatterns.contains(where: { lowercased.contains($0) }) {
            return true
        }
        
        // Skip very short lines that are likely not directions
        if line.count < 3 {
            return true
        }
        
        return false
    }
    
    private func isDirectionStep(_ line: String) -> Bool {
        // Check for step numbers at the beginning
        let stepNumberPatterns = [
            /^\d+\.\s*/, // 1. 2. etc.
            /^\d+\)\s*/, // 1) 2) etc.
            /^[Ss]tep\s*\d+:?\s*/, // Step 1: Step 2 etc.
            /^\d+:\s*/, // 1: 2: etc.
            /^\d+\s+-\s*/, // 1 - 2 - etc.
            /^\s*\d+\.\s*/, // Indented numbered steps like "    1. "
            /^\s*[Ss]tep\s*\d+:?\s*/, // Indented Step 1: Step 2 etc.
        ]
        
        for pattern in stepNumberPatterns {
            if line.matches(of: pattern).count > 0 {
                return true
            }
        }
        
        return false
    }
    
    private func cleanIngredientText(_ text: String) -> String {
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common bullet points and list delimiters
        let bulletPatterns = [
            /^•\s*/, // Bullet point
            /^-\s*/, // Dash
            /^\*\s*/, // Asterisk
            /^\+\s*/, // Plus sign
            /^>\s*/, // Greater than
            /^→\s*/, // Arrow
            /^▪\s*/, // Small bullet
            /^▫\s*/, // White bullet
            /^‣\s*/, // Triangular bullet
            /^⁃\s*/, // Hyphen bullet
            /^\d+\.\s*/, // Numbered list with period: 1., 2., etc.
            /^\d+\)\s*/, // Numbered list with parenthesis: 1), 2), etc.
        ]
        
        for pattern in bulletPatterns {
            cleanedText = cleanedText.replacing(pattern, with: "")
        }
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanDirectionText(_ text: String) -> String {
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove step numbers at the beginning (including indented ones)
        let stepNumberPatterns = [
            /^\d+\.\s*/, // 1. 2. etc.
            /^\d+\)\s*/, // 1) 2) etc.
            /^[Ss]tep\s*\d+:?\s*/, // Step 1: Step 2 etc.
            /^\d+:\s*/, // 1: 2: etc.
            /^\d+\s+-\s*/, // 1 - 2 - etc.
            /^\s*\d+\.\s*/, // Indented numbered steps like "    1. "
            /^\s*[Ss]tep\s*\d+:?\s*/, // Indented Step 1: Step 2 etc.
        ]
        
        for pattern in stepNumberPatterns {
            cleanedText = cleanedText.replacing(pattern, with: "")
        }
        
        // Clean up any extra whitespace that might be left
        cleanedText = cleanedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    #if os(macOS)
    private func loadImageFromSecureURL(_ url: URL) {
        // Start accessing the security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Load the image while we have access
        if let image = loadImage(from: url) {
            selectedImage = image
        }
    }
    
    private func loadImage(from url: URL) -> CGImage? {
        do {
            // Read the file data first
            let imageData = try Data(contentsOf: url)
            
            // Create image source from data instead of URL
            guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                print("Failed to create image from data")
                return nil
            }
            return cgImage
        } catch {
            print("Failed to read image data: \(error)")
            return nil
        }
    }
    #endif
}



#Preview {
    ScanTextForRecipeView(
        viewModel: .constant(RecipeDetailEditViewModel(recipe: Recipe(id: "test", name: "Test Recipe"))),
        initialTarget: .ingredients
    )
} 
