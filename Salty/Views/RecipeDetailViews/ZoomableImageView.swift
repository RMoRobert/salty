//
//  ZoomableImageView.swift
//  Salty
//
//  An image that can be pinched, dragged and double-tapped, driven by an `ImageZoomState`.
//

import SwiftUI

struct ZoomableImageView: View {
    let image: Image
    let zoom: ImageZoomState

    /// The pinch's and the drag's last reported values, so each update applies only the change.
    @State private var lastMagnification: CGFloat = 1
    @State private var lastTranslation: CGSize = .zero

    var body: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(zoom.scale)
            .offset(zoom.offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { zoom.containerSize = $0 }
            .gesture(
                SimultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom.magnify(by: value.magnification / lastMagnification)
                            lastMagnification = value.magnification
                        }
                        .onEnded { _ in lastMagnification = 1 },
                    DragGesture()
                        .onChanged { value in
                            zoom.pan(by: CGSize(width: value.translation.width - lastTranslation.width,
                                                height: value.translation.height - lastTranslation.height))
                            lastTranslation = value.translation
                        }
                        .onEnded { _ in lastTranslation = .zero }
                )
            )
            // Tap count is needed here, which a Button can't give.
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.3)) { zoom.toggle() }
            }
            .onKeyPress(.space) {
                withAnimation(.easeInOut(duration: 0.3)) { zoom.toggle() }
                return .handled
            }
            .focusable()
            .focusEffectDisabled()
            .accessibilityLabel("Recipe image")
            .accessibilityZoomAction { action in
                switch action.direction {
                case .zoomIn: zoom.zoomIn()
                case .zoomOut: zoom.zoomOut()
                @unknown default: break
                }
            }
    }
}
