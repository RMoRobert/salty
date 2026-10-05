//
//  ImageZoomState.swift
//  Salty
//
//  Zoom and pan for the full-size recipe image, kept apart from the view so the limits can be tested.
//

import Foundation
import Observation

@MainActor
@Observable
final class ImageZoomState {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4
    /// One ⌘= or ⌘− step.
    static let stepFactor: CGFloat = 1.25
    /// Where a double-tap or Space zooms to from the fitted size.
    static let toggledScale: CGFloat = 2

    private(set) var scale: CGFloat = 1
    private(set) var offset: CGSize = .zero
    /// The view's size, which bounds how far a zoomed image can be panned.
    var containerSize: CGSize = .zero

    var isZoomed: Bool { scale > Self.minimumScale }

    func zoomIn() {
        scale = min(scale * Self.stepFactor, Self.maximumScale)
        clampOffset()
    }

    func zoomOut() {
        scale = max(scale / Self.stepFactor, Self.minimumScale)
        clampOffset()
    }

    func reset() {
        scale = Self.minimumScale
        offset = .zero
    }

    /// Double-tap and Space: zoom to 2x from the fitted size, back to fitted from anything else.
    func toggle() {
        if isZoomed { reset() } else { scale = Self.toggledScale }
    }

    /// Multiplies the scale by a pinch's change since its last update, within the limits.
    func magnify(by factor: CGFloat) {
        guard factor > 0 else { return }
        scale = min(max(scale * factor, Self.minimumScale), Self.maximumScale)
        clampOffset()
    }

    /// Moves a zoomed image by `delta`, never past its edges. A fitted image doesn't pan.
    func pan(by delta: CGSize) {
        guard isZoomed else { return }
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        clampOffset()
    }

    private func clampOffset() {
        let maxX = containerSize.width * (scale - 1) / 2
        let maxY = containerSize.height * (scale - 1) / 2
        offset = CGSize(width: min(max(offset.width, -maxX), maxX),
                        height: min(max(offset.height, -maxY), maxY))
    }
}
