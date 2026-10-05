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
/// Returns PNG-encoded data suitable for `PendingRecipeImage.replace(_:)`, or `nil` if the
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
    @Binding var pendingImage: PendingRecipeImage
    var body: some View {
        Button("Delete", role: .destructive) {
            pendingImage = .remove
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
    @Binding var pendingImage: PendingRecipeImage
    /// On macOS, always shown for discoverability but disabled when the clipboard holds no image.
    /// On iOS, `.confirmationDialog` hides disabled buttons, so we only render it when an image is
    /// available (matching the platform convention of omitting unavailable actions).
    @ViewBuilder var body: some View {
        let clipboardImageData = imageDataFromClipboard()
        #if os(iOS)
        if let clipboardImageData {
            Button("Paste from Clipboard") {
                pendingImage = .replace(clipboardImageData)
            }
        }
        #else
        Button("Paste from Clipboard") {
            if let clipboardImageData {
                pendingImage = .replace(clipboardImageData)
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

/// Picks, pastes, drops, captures, or deletes a recipe's photo.
///
/// Every choice lands in `pendingImage`, never on disk: the owning view model applies it when the
/// recipe is saved, so cancelling the editor really does leave the stored image alone.
struct RecipeImageEditView: View {
    private let logger = Logger(subsystem: "Salty", category: "RecipeImage")
    @Binding var recipe: Recipe
    @Binding var pendingImage: PendingRecipeImage
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
            if let imageData = pendingImage.previewData(for: recipe), let image = createCGImage(from: imageData) {

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
                    DeleteImageButton(pendingImage: $pendingImage)
                    SelectImageFileButton(showingImageFilePicker: $showingImageFilePicker)
                    PasteImageButton(pendingImage: $pendingImage)
                    TakePhotoButton(showingCamera: $showingCamera)
                }
                .confirmationDialog("Image Options", isPresented: $showingImageMenu) {
                    DeleteImageButton(pendingImage: $pendingImage)
                    SelectImageFileButton(showingImageFilePicker: $showingImageFilePicker)
                    PasteImageButton(pendingImage: $pendingImage)
                    TakePhotoButton(showingCamera: $showingCamera)
                }
                .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                    providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                        guard let data else { return }
                        // The provider callback is nonisolated; hop to the main actor to mutate state.
                        Task { @MainActor in
                            pendingImage = .replace(data)
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
                                pendingImage = .remove
                            }

                            Button("Select a File") {
                                showingImageFilePicker = true
                            }

                            Button("Select a Photo") {
                                showingPhotoPicker = true
                            }

                            PasteImageButton(pendingImage: $pendingImage)
                        }
                        .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                            providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                                guard let data else { return }
                                // Provider callback is nonisolated; hop to the main actor to mutate state.
                                Task { @MainActor in pendingImage = .replace(data) }
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
                    PasteImageButton(pendingImage: $pendingImage)
                    TakePhotoButton(showingCamera: $showingCamera)
                }
                .confirmationDialog("Add Image", isPresented: $showingImageMenu) {
                    SelectImageFileButton(showingImageFilePicker: $showingImageFilePicker)
                    PasteImageButton(pendingImage: $pendingImage)
                    TakePhotoButton(showingCamera: $showingCamera)
                }
                .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                    providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                        guard let data else { return }
                        // The provider callback is nonisolated; hop to the main actor to mutate state.
                        Task { @MainActor in
                            pendingImage = .replace(data)
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

                        PasteImageButton(pendingImage: $pendingImage)
                    }
                    .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                        providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                            guard let data else { return }
                            // Provider callback is nonisolated; hop to the main actor to mutate state.
                            Task { @MainActor in pendingImage = .replace(data) }
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
                        pendingImage = .replace(imageData)
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
                            pendingImage = .replace(data)
                        }
                    }
                }
            }),
            matching: .images
        )
        #endif
        #if os(macOS)
        .sheet(isPresented: $showingCamera) {
            MacCameraCaptureView(capturedImage: .init(get: { nil }, set: { cgImage in
                if let cgImage = cgImage {
                    // Convert CGImage to Data
                    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                    if let data = bitmapRep.representation(using: .png, properties: [:]) {
                        pendingImage = .replace(data)
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
    @Previewable @State var pendingImage = PendingRecipeImage.unchanged
    return RecipeImageEditView(recipe: $recipe, pendingImage: $pendingImage)
}
