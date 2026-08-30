//
//  WindowContentBelowTitlebar.swift
//  Salty
//
//  Created by Robert on 8/19/26.
//

import SwiftUI

#if os(macOS)
import AppKit

/// Keeps a window's content out of the titlebar and toolbar strip.
///
/// SwiftUI gives macOS 26 windows `.fullSizeContentView`, so content is laid out behind the glass
/// titlebar and shows through it. That is the intended look when the content is a scroll view, but
/// this window's content is an `HSplitView`, and `NSSplitView` draws its divider across its entire
/// height -- so the divider came out as a hairline running up through the toolbar and the title.
///
/// The inset has to come from the window, because the split view won't take it from SwiftUI:
/// `.safeAreaPadding(.top)` leaves its frame at the full window height (measured, not assumed).
/// Clearing the style mask instead moves the content view down to `contentLayoutRect`, which brings
/// the divider with it.
struct WindowContentBelowTitlebar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        StyleMaskView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Applied on every move into a window rather than once at creation: SwiftUI sets the style mask
    /// itself when it builds the window, so this needs to run after that rather than race it.
    final class StyleMaskView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.styleMask.remove(.fullSizeContentView)
        }
    }
}

extension View {
    /// Stops this window's content being laid out behind the titlebar. See
    /// ``WindowContentBelowTitlebar`` for why an `HSplitView` window needs it.
    func windowContentBelowTitlebar() -> some View {
        background(WindowContentBelowTitlebar())
    }
}
#endif
