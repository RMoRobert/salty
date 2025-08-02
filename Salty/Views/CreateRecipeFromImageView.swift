//
//  CreateRecipeFromImageView.swift
//  Salty
//
//  Created by Robert on 7/13/25.
//

import SwiftUI
import PhotosUI
import VisionKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct CreateRecipeFromImageView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ocrService = RecipeOCRService()
    @State private var selectedImage: CGImage?
    @State private var multiPageScan: VNDocumentCameraScan?
    @State private var showingImagePicker = false
    @State private var showingDocumentScanner = false
    @State private var showingCamera = false
    @State private var showingFilePicker = false
    @State private var parsedRecipe: Recipe?
    @State private var showingRecipeEditor = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
                    } else {
                        ContentUnavailableView {
                            Label("No Image", systemImage: "photo")
                        } description: {
                            #if os(macOS)
                            Text("Choose an image to scan for recipe text.")
                            #else
                            Text("Choose or capture an image to scan for recipe text.")
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
                            TextField("Extracted Text", text: $ocrService.extractedText,  axis: .vertical)
                            .frame(maxHeight: 300)
                            .border(Color.secondary.opacity(0.3), width: 1)
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
                        if let multiPageScan = multiPageScan {
                            Task {
                                await ocrService.extractTextFromMultiPageScan(multiPageScan)
                            }
                        } else if let image = selectedImage {
                            Task {
                                await ocrService.extractText(from: image)
                            }
                        }
                    }
                    .disabled(selectedImage == nil || ocrService.isProcessing)
                    
                    Button("Create Recipe") {
                        createRecipeFromExtractedText()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ocrService.extractedText.isEmpty)
                }
                .padding(.horizontal)
                .padding([.top, .bottom], 8)
            }
            .navigationTitle("Create from Image")
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
        .sheet(isPresented: $showingRecipeEditor) {
            if let recipe = parsedRecipe {
                NavigationStack {
                    RecipeDetailEditMobileView(recipe: recipe, isNewRecipe: true, onNewRecipeSaved: { _ in
                        // Close the sheet after saving
                        showingRecipeEditor = false
                    })
                       // .frame(minWidth: 600, minHeight: 500)
                }
            }
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
        .sheet(isPresented: $showingRecipeEditor) {
            if let recipe = parsedRecipe {
                NavigationStack {
                    RecipeDetailEditDesktopView(recipe: recipe, isNewRecipe: true, onNewRecipeSaved: { _ in
                        // Close the sheet after saving
                        showingRecipeEditor = false
                    })
                    .frame(minWidth: 625, minHeight: 650)
                }
            }
        }
        #endif
    }
    
    private func createRecipeFromExtractedText() {
        let parser = RecipeFromTextParser()
        parsedRecipe = parser.parseRecipe(from: ocrService.extractedText)
        showingRecipeEditor = true
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

#if os(iOS)
// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: CGImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        if let uiImage = image as? UIImage,
                           let cgImage = uiImage.cgImage {
                            self.parent.selectedImage = cgImage
                        }
                    }
                }
            }
        }
    }
}
#endif

#if os(iOS)
// MARK: - Document Scanner
struct DocumentScanner: UIViewControllerRepresentable {
    @Binding var selectedImage: CGImage?
    @Binding var multiPageScan: VNDocumentCameraScan?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        
        init(_ parent: DocumentScanner) {
            self.parent = parent
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Combine all pages into one image
            let pageCount = scan.pageCount
            if pageCount == 1 {
                // Single page - use directly
                let uiImage = scan.imageOfPage(at: 0)
                if let cgImage = uiImage.cgImage {
                    parent.selectedImage = cgImage
                }
            } else {
                // Multiple pages - use the first page for display, but note that OCR will process all pages
                let uiImage = scan.imageOfPage(at: 0)
                if let cgImage = uiImage.cgImage {
                    parent.selectedImage = cgImage
                }
                
                // Store the scan for multi-page OCR processing
                parent.multiPageScan = scan
            }
            parent.dismiss()
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    @Binding var selectedImage: CGImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage,
               let cgImage = uiImage.cgImage {
                parent.selectedImage = cgImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

#Preview {
    CreateRecipeFromImageView()
}
