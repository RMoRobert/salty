//
//  MultiWindowSupport.swift
//  Salty
//  Created by Robert on 8/19/2026
//
//  Whether this device can put a second app window on screen.
//

#if os(iOS)
import UIKit
#endif

/// Whether `openWindow` can actually open a window here.
///
/// macOS always can. On iOS it depends on the device: iPad supports multiple scenes (I'm opting in
/// with `UIApplicationSupportsMultipleScenes` in Info.plist),
///
/// Deliberately not `@Environment(\.supportsMultipleWindows)` since that only applies to a specific
/// view, and menu bar `Commands` don't have one.
enum MultiWindowSupport {
    @MainActor
    static var isSupported: Bool {
        #if os(macOS)
        true
        #else
        UIApplication.shared.supportsMultipleScenes
        #endif
    }
}
