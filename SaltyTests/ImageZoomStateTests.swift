//
//  ImageZoomStateTests.swift
//  SaltyTests
//

import Testing
import Foundation
@testable import Salty

@MainActor
struct ImageZoomStateTests {
    private func zoom() -> ImageZoomState {
        let zoom = ImageZoomState()
        zoom.containerSize = CGSize(width: 400, height: 300)
        return zoom
    }

    @Test func zoomStepsStayWithinTheLimits() {
        let zoom = zoom()
        zoom.zoomOut()
        #expect(zoom.scale == 1)
        for _ in 0..<20 { zoom.zoomIn() }
        #expect(zoom.scale == ImageZoomState.maximumScale)
    }

    @Test func aFittedImageDoesNotPan() {
        let zoom = zoom()
        zoom.pan(by: CGSize(width: 50, height: 50))
        #expect(zoom.offset == .zero)
    }

    @Test func panningStopsAtTheImageEdges() {
        let zoom = zoom()
        zoom.toggle()   // 2x: the image overhangs by half the container on each axis
        zoom.pan(by: CGSize(width: 1_000, height: -1_000))
        #expect(zoom.offset == CGSize(width: 200, height: -150))
    }

    @Test func zoomingOutPullsTheOffsetBackInBounds() {
        let zoom = zoom()
        zoom.toggle()
        zoom.pan(by: CGSize(width: 1_000, height: 0))
        zoom.zoomOut()   // 1.6x
        #expect(abs(zoom.offset.width - 120) < 0.001)
        zoom.reset()
        #expect(zoom.offset == .zero)
        #expect(!zoom.isZoomed)
    }

    @Test func magnifyClampsAndIgnoresNonsense() {
        let zoom = zoom()
        zoom.magnify(by: 0.1)
        #expect(zoom.scale == 1)
        zoom.magnify(by: 10)
        #expect(zoom.scale == ImageZoomState.maximumScale)
        zoom.magnify(by: 0)
        #expect(zoom.scale == ImageZoomState.maximumScale)
    }

    @Test func toggleGoesToTwiceAndBack() {
        let zoom = zoom()
        zoom.toggle()
        #expect(zoom.scale == 2)
        zoom.zoomIn()
        zoom.toggle()
        #expect(zoom.scale == 1)
    }
}
