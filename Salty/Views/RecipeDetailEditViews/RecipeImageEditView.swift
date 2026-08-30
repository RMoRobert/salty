//
//  RecipeImageEditView.swift
//  Salty
//
//  Created by Robert on 5/31/23.
//

import SwiftUI
import OSLog
import SaltyCore
#if os(iOS)
import PhotosUI
import UIKit
#elseif os(macOS)
import AVFoundation
import AppKit
#endif

/// Reads image data from the system clipboard/pasteboard, if any is present.
/// Returns PNG-encoded data suitable for `Recipe.setImage(_:)`, or `nil` if the
/// clipboard does not contain an image.
@MainActor
private func imageDataFromClipboard() -> Data? {
    #if os(iOS)
    let pasteboard = UIPasteboard.general
    guard pasteboard.hasImages, let image = pasteboard.image else { return nil }
    return image.pngData()
    #elseif os(macOS)
    guard let image = NSImage(pasteboard: NSPasteboard.general),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
    #endif
}

private struct DeleteImageButton: View {
    @Binding var recipe: Recipe
    var body: some View {
        Button("Delete", role: .destructive) {
            recipe.removeImage()
        }
    }
}

private struct SelectImageFileButton: View {
    @Binding var showingImageFilePicker: Bool
    var body: some View {
        Button("Select a File") {
            showingImageFilePicker = true
        }
    }
}

private struct PasteImageButton: View {
    @Binding var recipe: Recipe
    /// On macOS, always shown for discoverability but disabled when the clipboard holds no image.
    /// On iOS, `.confirmationDialog` hides disabled buttons, so we only render it when an image is
    /// available (matching the platform convention of omitting unavailable actions).
    @ViewBuilder var body: some View {
        let clipboardImageData = imageDataFromClipboard()
        #if os(iOS)
        if let clipboardImageData {
            Button("Paste from Clipboard") {
                recipe.setImage(clipboardImageData)
            }
        }
        #else
        Button("Paste from Clipboard") {
            if let clipboardImageData {
                recipe.setImage(clipboardImageData)
            }
        }
        .disabled(clipboardImageData == nil)
        #endif
    }
}

private struct TakePhotoButton: View {
    @Binding var showingCamera: Bool
    @ViewBuilder var body: some View {
        #if os(macOS)
        Button("Take Photo") {
            showingCamera = true
        }
        #endif
    }
}

struct RecipeImageEditView: View {
    private let logger = Logger(subsystem: "Salty", category: "RecipeImage")
    @Binding var recipe: Recipe
    @State private var dragOver = false
    @State private var showingImageFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var showingImageMenu = false
    @State private var showingCamera = false

    @State var imageFrameSize: CGFloat = 100

    private func createCGImage(from imageData: Data) -> CGImage? {
        #if os(iOS)
        guard let uiImage = UIImage(data: imageData) else { return nil }
        return uiImage.cgImage
        #elseif os(macOS)
        guard let nsImage = NSImage(data: imageData) else { return nil }
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
    
    var body: some View {
        VStack {
            if let imageData = recipe.fullImageData, let image = createCGImage(from: imageData) {

                #if os(macOS)
                Button(action: {
                    showingImageMenu = true
                }) {
                    Image(image, scale: 1, label: Text("Recipe Image"))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaledToFit()
                            .frame(width: imageFrameSize, height: imageFrameSize, alignment: .center)
                            .border(.thickMaterial)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    DeleteImageButton(recipe: $recipe)
                    SelectImageFileButton(showingImageFilePicker: $showingImageFilePicker)
                    PasteImageButton(recipe: $recipe)
                    TakePhotoButton(showingCamera: $showingCamera)
                }
                .confirmationDialog("Image Options", isPresented: $showingImageMenu) {
                    DeleteImageButton(recipe: $recipe)
                    SelectImageFileButton(showingImageFilePicker: $showingImageFilePicker)
                    PasteImageButton(recipe: $recipe)
                    TakePhotoButton(showingCamera: $showingCamera)
                }
                .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                    providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                        guard let data else { return }
                        // The provider callback is nonisolated; hop to the main actor to mutate state.
                        Task { @MainActor in
                            recipe.setImage(data)
                        }
                    })
                    return true
                }
                #else
                Image(image, scale: 1, label: Text("Recipe Image"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaledToFit()
                        .frame(width: imageFrameSize, height: imageFrameSize, alignment: .center)
                        .border(.thickMaterial)
                        .onTapGesture {
                            showingImageMenu = true
                        }
                        .confirmationDialog("Image Options", isPresented: $showingImageMenu) {
                            Button("Delete", role: .destructive) {
                                recipe.removeImage()
                            }

                            Button("Select a File") {
                                showingImageFilePicker = true
                            }

                            Button("Select a Photo") {
                                showingPhotoPicker = true
                            }

                            PasteImageButton(recipe: $recipe)
                        }
                        .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                            providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                                guard let data else { return }
                                // Provider callback is nonisolated; hop to the main actor to mutate state.
                                Task { @MainActor in recipe.setImage(data) }
                            })
                            return true
                        }
                #endif
            }
            else {
                #if os(macOS)
                Button(action: {
                    showingImageMenu = true
                }) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white)
                        .frame(width: imageFrameSize, height: imageFrameSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4, dash: [5]))
                        )
                        .overlay(Label("Add", systemImage: "plus")
                            .foregroundStyle(.gray)
                            .labelStyle(.iconOnly)
                        )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    SelectImageFileButton(showingImageFilePicker: $showingImageFilePicker)
                    PasteImageButton(recipe: $recipe)
                    TakePhotoButton(showingCamera: $showingCamera)
                }
                .confirmationDialog("Add Image", isPresented: $showingImageMenu) {
                    SelectImageFileButton(showingImageFilePicker: $showingImageFilePicker)
                    PasteImageButton(recipe: $recipe)
                    TakePhotoButton(showingCamera: $showingCamera)
                }
                .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                    providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                        guard let data else { return }
                        // The provider callback is nonisolated; hop to the main actor to mutate state.
                        Task { @MainActor in
                            recipe.setImage(data)
                        }
                    })
                    return true
                }
                #else
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white)
                    .frame(width: imageFrameSize, height: imageFrameSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4, dash: [5]))
                    )
                    .overlay(Label("Add", systemImage: "plus")
                        .foregroundStyle(.gray)
                        .labelStyle(.iconOnly)
                    )
                    .onTapGesture {
                        showingImageMenu = true
                    }
                    .confirmationDialog("Add Image", isPresented: $showingImageMenu) {
                        Button("Select a File") {
                            showingImageFilePicker = true
                        }

                        Button("Select a Photo") {
                            showingPhotoPicker = true
                        }

                        PasteImageButton(recipe: $recipe)
                    }
                    .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                        providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                            guard let data else { return }
                            // Provider callback is nonisolated; hop to the main actor to mutate state.
                            Task { @MainActor in recipe.setImage(data) }
                        })
                        return true
                    }
                #endif
            }
        }
        .fileImporter(
            isPresented: $showingImageFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        // Start accessing the security-scoped resource
                        guard url.startAccessingSecurityScopedResource() else {
                            return
                        }
                        
                        defer {
                            // Stop accessing the security-scoped resource
                            url.stopAccessingSecurityScopedResource()
                        }
                        
                        let imageData = try Data(contentsOf: url)
                        recipe.setImage(imageData)
                    } catch {
                        logger.error("Error loading image data: \(error)")
                    }
                }
            case .failure(let error):
                logger.error("Error selecting image: \(error.localizedDescription)")
            }
        }
        #if os(iOS)
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: .init(get: { nil }, set: { item in
                Task { @MainActor in
                    if let item = item {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            recipe.setImage(data)
                        }
                    }
                }
            }),
            matching: .images
        )
        #endif
        #if os(macOS)
        .sheet(isPresented: $showingCamera) {
            RecipeImageCameraView(selectedImage: .init(get: { nil }, set: { cgImage in
                if let cgImage = cgImage {
                    // Convert CGImage to Data
                    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                    if let data = bitmapRep.representation(using: .png, properties: [:]) {
                        recipe.setImage(data)
                    }
                }
            }))
            .frame(minWidth: 600, minHeight: 500)
        }
        #endif
    }
}

#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    return RecipeImageEditView(recipe: $recipe)
}

#if os(macOS)
// MARK: - macOS Camera View
struct RecipeImageCameraView: NSViewControllerRepresentable {
    @Binding var selectedImage: CGImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeNSViewController(context: Context) -> NSViewController {
        let cameraView = RecipeImageCameraViewController()
        cameraView.delegate = context.coordinator
        return cameraView
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, RecipeImageCameraViewControllerDelegate {
        let parent: RecipeImageCameraView
        
        init(_ parent: RecipeImageCameraView) {
            self.parent = parent
        }
        
        func cameraViewController(_ controller: RecipeImageCameraViewController, didCaptureImage image: CGImage) {
            parent.selectedImage = image
            parent.dismiss()
        }
        
        func cameraViewControllerDidCancel(_ controller: RecipeImageCameraViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - macOS Camera View Controller
@MainActor protocol RecipeImageCameraViewControllerDelegate: AnyObject {
    func cameraViewController(_ controller: RecipeImageCameraViewController, didCaptureImage image: CGImage)
    func cameraViewControllerDidCancel(_ controller: RecipeImageCameraViewController)
}

class RecipeImageCameraViewController: NSViewController {
    private let logger = Logger(subsystem: "Salty", category: "RecipeImage")
    weak var delegate: RecipeImageCameraViewControllerDelegate?
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
            logger.debug("No camera available")
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
            logger.error("Error setting up camera: \(error)")
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
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.layer?.backgroundColor = NSColor.secondarySystemFill.cgColor.copy(alpha: 0.2)
        view.addSubview(captureButton)
        
        // Create cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelCapture))
        cancelButton.bezelStyle = .push
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.layer?.backgroundColor = NSColor.secondarySystemFill.cgColor.copy(alpha: 0.2)
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
        // AVCaptureSession start/stop must run off the main thread. The session is created on the main
        // actor; `nonisolated(unsafe)` hands the (thread-safe) session to a background queue without
        // tripping Sendable checks.
        nonisolated(unsafe) let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session?.startRunning()
        }
    }

    private func stopSession() {
        nonisolated(unsafe) let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session?.stopRunning()
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
extension RecipeImageCameraViewController: AVCapturePhotoCaptureDelegate {
    // AVFoundation invokes this on a background queue, so it must be nonisolated; we decode the photo
    // here and hop to the main actor to notify the (MainActor) delegate.
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            logger.error("Error capturing photo: \(error)")
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.error("Failed to create CGImage from photo")
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.cameraViewController(self, didCaptureImage: cgImage)
        }
    }
}
#endif
