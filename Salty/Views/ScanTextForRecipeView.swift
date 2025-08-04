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
        let parser = RecipeFromTextParser()
        let scannedRecipe = parser.parseRecipe(from: ocrService.extractedText)
        
        switch targetSection {
        case .introduction:
            //  scanned text to existing introduction
            let newText = ocrService.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newText.isEmpty {
                if viewModel.recipe.introduction.isEmpty {
                    viewModel.recipe.introduction = newText
                } else {
                    viewModel.recipe.introduction += "\n\n" + newText
                }
            }
        case .ingredients:
            // Add scanned ingredients to existing ones
            for ingredient in scannedRecipe.ingredients {
                viewModel.recipe.ingredients.append(ingredient)
            }
        case .directions:
            // Add scanned directions to existing ones
            for direction in scannedRecipe.directions {
                viewModel.recipe.directions.append(direction)
            }
        }
        
        dismiss()
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
