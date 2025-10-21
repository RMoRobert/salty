//
//  CreateRecipeFromImageView.swift
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
import AVFoundation
#endif

struct CreateRecipeFromImageView: View {
    @Environment(\.dismiss) private var dismiss
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
    @State private var parsedRecipe: Recipe?
    @State private var showingRecipeEditor = false
    @State private var showingTextParsingTips = false
    
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
                        if ocrService.extractedText.isEmpty {
                            Group {
                                Text("Image added!")
                                    .fontWeight(.semibold)
                                    .padding()
                                Text("Select \"Extract Text\" to scan for text, then, select \"Create Recipe.\"")
                                Button("Tips") {
                                    showingTextParsingTips = true
                                }
                                .padding(.bottom)
                            }
                            
                        }
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
#elseif os(macOS)
                    Button("Camera (beta)") {
                        showingCamera = true
                    }
                    .buttonStyle(.bordered)
#endif
                    Button("From File") {
                        showingFilePicker = true
                    }
                    .buttonStyle(.bordered)

                }
                .padding(.horizontal)
                
                // OCR results
                if !ocrService.extractedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $ocrService.extractedText)
                            .frame(maxHeight: 800)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary).opacity(0.5)
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
#if !os(macOS)
            .navigationTitle("Create from Image")
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
        .alert(
            "Tips for Best Results",
            isPresented: $showingTextParsingTips,
            actions: {},
            message: {
                Text("For best results:\n\n• Remove excess text like page numbers.\n\n• Provide titles like \"Directions\" or \"Ingredients\" on their own line before the relevant sections to improve detection. Number or label direction steps if possible. (Other helpful labels include \"yield,\" \"servings,\" and \"introduction.\")\n\n• For certain recipes, it may be easier to use the built-in \"Scan Text\" feature on iPhone/iPad in any text field or the \"Edit as Text (Bulk Edit)\" feature for directions or ingredients.")
            })
        #endif
        .fileImporter(
            isPresented: $showingFilePicker,
            // TODO: Also allow PDF, either convert to image or read text from PDF directly
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
                    #if os(macOS)
                    RecipeDetailEditDesktopView(recipe: recipe, isNewRecipe: true, onNewRecipeSaved: { _ in
                        // Close the sheet after saving
                        showingRecipeEditor = false
                    })
                    .frame(minWidth: 625, minHeight: 650)
                    #else
                    RecipeDetailEditMobileView(recipe: recipe, isNewRecipe: true, onNewRecipeSaved: { _ in
                        // Close the sheet after saving
                        showingRecipeEditor = false
                    })
                    #endif
                }
            }
        }
#if os(macOS)
        .sheet(isPresented: $showingCamera) {
            MacCameraView(selectedImage: $selectedImage)
                .frame(minWidth: 600, minHeight: 500)
        }
#endif
    }
    
    private func createRecipeFromExtractedText() {
        let parser = RecipeFromTextParser()
        parsedRecipe = parser.parseRecipe(from: ocrService.extractedText)
        showingRecipeEditor = true
    }
    
    //if os(macOS)
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
    //endif
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

#if os(macOS)
// MARK: - macOS Camera View
struct MacCameraView: NSViewControllerRepresentable {
    @Binding var selectedImage: CGImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeNSViewController(context: Context) -> NSViewController {
        let cameraView = MacCameraViewController()
        cameraView.delegate = context.coordinator
        return cameraView
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MacCameraViewControllerDelegate {
        let parent: MacCameraView
        
        init(_ parent: MacCameraView) {
            self.parent = parent
        }
        
        func cameraViewController(_ controller: MacCameraViewController, didCaptureImage image: CGImage) {
            parent.selectedImage = image
            parent.dismiss()
        }
        
        func cameraViewControllerDidCancel(_ controller: MacCameraViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - macOS Camera View Controller
protocol MacCameraViewControllerDelegate: AnyObject {
    func cameraViewController(_ controller: MacCameraViewController, didCaptureImage image: CGImage)
    func cameraViewControllerDidCancel(_ controller: MacCameraViewController)
}

class MacCameraViewController: NSViewController {
    weak var delegate: MacCameraViewControllerDelegate?
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        startSession()
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopSession()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        captureSession.sessionPreset = .photo
        
        // Get the default camera
        guard let camera = AVCaptureDevice.default(for: .video) else {
            print("No camera available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            photoOutput = AVCapturePhotoOutput()
            if let photoOutput = photoOutput, captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    private func setupUI() {
        view.wantsLayer = true
        
        // Set a minimum size for the view
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        
        // Create preview layer
        guard let captureSession = captureSession else { return }
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = .resizeAspectFill
        
        if let previewLayer = videoPreviewLayer {
            view.layer?.addSublayer(previewLayer)
        }
        
        // Create a semi-transparent background for buttons
        let buttonBackground = NSView()
        buttonBackground.wantsLayer = true
        buttonBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
        buttonBackground.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonBackground)
        
        // Create capture button
        let captureButton = NSButton(title: "Capture", target: self, action: #selector(capturePhoto))
        captureButton.bezelStyle = .push
//        captureButton.isBordered = true
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.layer?.backgroundColor = NSColor.secondarySystemFill.cgColor.copy(alpha: 0.2)
//        captureButton.wantsLayer = true
//        captureButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
//        captureButton.layer?.cornerRadius = 8
//        captureButton.layer?.borderWidth = 1
//        captureButton.layer?.borderColor = NSColor.white.cgColor
//        captureButton.attributedTitle = NSAttributedString(
//            string: "Capture",
//            attributes: [.foregroundColor: NSColor.white, .font: NSFont.boldSystemFont(ofSize: 14)]
//        )
        view.addSubview(captureButton)
        
        // Create cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelCapture))
        cancelButton.bezelStyle = .push
//        cancelButton.isBordered = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.layer?.backgroundColor = NSColor.secondarySystemFill.cgColor.copy(alpha: 0.2)
//        cancelButton.wantsLayer = true
//        cancelButton.layer?.cornerRadius = 8
//        cancelButton.layer?.borderWidth = 1
//        cancelButton.layer?.borderColor = NSColor.white.cgColor
//        cancelButton.attributedTitle = NSAttributedString(
//            string: "Cancel",
//            attributes: [.foregroundColor: NSColor.white, .font: NSFont.boldSystemFont(ofSize: 14)]
//        )
        view.addSubview(cancelButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Button background
            buttonBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttonBackground.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            buttonBackground.heightAnchor.constraint(equalToConstant: 80),
            
            // Capture button
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            captureButton.widthAnchor.constraint(equalToConstant: 120),
            captureButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Cancel button
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 100),
            cancelButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        videoPreviewLayer?.frame = view.bounds
    }
    
    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    private func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
    
    @objc private func capturePhoto() {
        guard let photoOutput = photoOutput else { return }
        
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    @objc private func cancelCapture() {
        delegate?.cameraViewControllerDidCancel(self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension MacCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to create CGImage from photo")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.cameraViewController(self!, didCaptureImage: cgImage)
        }
    }
}
#endif

#Preview {
    CreateRecipeFromImageView()
}
