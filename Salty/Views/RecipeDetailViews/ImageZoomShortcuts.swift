//
//  ImageZoomShortcuts.swift
//  Salty
//

import SwiftUI

/// ⌘=, ⌘− and ⌘0 for the image: invisible buttons, so the shortcuts work wherever focus is inside the
/// sheet. Hidden from VoiceOver, which zooms through `ZoomableImageView`'s zoom action instead.
struct ImageZoomShortcuts: View {
    let zoom: ImageZoomState

    var body: some View {
        Group {
            Button("Zoom In") { withAnimation(.easeInOut(duration: 0.2)) { zoom.zoomIn() } }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { withAnimation(.easeInOut(duration: 0.2)) { zoom.zoomOut() } }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { withAnimation(.easeInOut(duration: 0.3)) { zoom.reset() } }
                .keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}
