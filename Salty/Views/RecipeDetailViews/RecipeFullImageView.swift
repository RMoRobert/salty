//
//  RecipeFullImageView.swift
//  Salty
//
//  Created by Robert on 7/6/25.
//

import SwiftUI
import SharingGRDB

struct ZoomableImageView: View {
    let image: Image
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = min(scale * 1.25, 4.0)
        }
    }
    
    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = max(scale / 1.25, 1.0)
            if scale == 1.0 {
                offset = .zero
            }
        }
    }
    
    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.3)) {
            scale = 1.0
            offset = .zero
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 1.0), 4.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                // Snap back to bounds if needed
                                if scale < 1.0 {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        scale = 1.0
                                        offset = .zero
                                    }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                let delta = CGSize(
                                    width: value.translation.width - lastOffset.width,
                                    height: value.translation.height - lastOffset.height
                                )
                                lastOffset = value.translation
                                
                                // Only allow dragging when zoomed in
                                if scale > 1.0 {
                                    let maxOffsetX = (geometry.size.width * (scale - 1.0)) / 2
                                    let maxOffsetY = (geometry.size.height * (scale - 1.0)) / 2
                                    
                                    offset = CGSize(
                                        width: max(-maxOffsetX, min(maxOffsetX, offset.width + delta.width)),
                                        height: max(-maxOffsetY, min(maxOffsetY, offset.height + delta.height))
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = .zero
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                        } else {
                            scale = 2.0
                        }
                    }
                }
                .onKeyPress(.space, action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                        } else {
                            scale = 2.0
                        }
                    }
                    return .handled
                })
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ZoomIn"))) { _ in
                    zoomIn()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ZoomOut"))) { _ in
                    zoomOut()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetZoom"))) { _ in
                    resetZoom()
                }
        }
    }
}

struct RecipeFullImageView: View {
    let recipe: Recipe
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif
    
    var body: some View {
        VStack(spacing: 0) {
            if let imageURL = recipe.fullImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let image):
                        ZoomableImageView(image: image)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure(_):
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Failed to load image")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Unknown error loading image")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No image available")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("\(recipe.name) - Recipe Image")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CmdPlusPressed"))) { _ in
            NotificationCenter.default.post(name: NSNotification.Name("ZoomIn"), object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CmdMinusPressed"))) { _ in
            NotificationCenter.default.post(name: NSNotification.Name("ZoomOut"), object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CmdZeroPressed"))) { _ in
            NotificationCenter.default.post(name: NSNotification.Name("ResetZoom"), object: nil)
        }

        #if os(macOS)
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                if event.modifierFlags.contains(.command) {
                    switch event.characters {
                    case "=":
                        NotificationCenter.default.post(name: NSNotification.Name("ZoomIn"), object: nil)
                        return nil
                    case "-":
                        NotificationCenter.default.post(name: NSNotification.Name("ZoomOut"), object: nil)
                        return nil
                    case "0":
                        NotificationCenter.default.post(name: NSNotification.Name("ResetZoom"), object: nil)
                        return nil
                    default:
                        break
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        #endif
    }
}

#Preview {
    RecipeFullImageView(recipe: SampleData.sampleRecipes[0])
}
