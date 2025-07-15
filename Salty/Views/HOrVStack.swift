//
//  HOrVStack.swift
//  Salty
//
//  Created by Robert on 7/28/23.
//

import SwiftUI

/// Returns HStackLayout or VStackLayout, depending on UI size class and OS (assume macOS can always handle H)
struct HOrVStack<Content: View>: View {
    @State var alignFirstTextLeadingIfHStack = false
    var spacingIfHStack: CGFloat? = nil
    var spacingIfVStack: CGFloat? = nil
    
#if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
#else
    enum UserInterfaceSizeClass {
        case compact
        case regular
        case none
    }
    let horizontalSizeClass = UserInterfaceSizeClass.regular
#endif
    
    @ViewBuilder var content: () -> Content
    
    var currentLayout: AnyLayout {
        if horizontalSizeClass == .regular {
            if alignFirstTextLeadingIfHStack {
                if let spacing = spacingIfHStack {
                    return AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: spacing))
                } else {
                    return AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                }
            } else {
                if let spacing = spacingIfHStack {
                    return AnyLayout(HStackLayout(spacing: spacing))
                } else {
                    return AnyLayout(HStackLayout())
                }
            }
        } else {
            if let spacing = spacingIfVStack {
                return AnyLayout(VStackLayout(spacing: spacing))
            }
            else {
                return AnyLayout(VStackLayout())
            }
        }
    }

    var body: some View {
        currentLayout(content)
    }
}

///// Returns HStackLayout if macOS, else  VStackLayout (regardless of UI size class)
//struct HOrVStackHM<Content: View> View {
//    @State var alignFirstTextLeadingIfHStack = false
//    enum UserInterfaceSizeClass {
//        case compact
//        case regular
//        case none
//    }
//    #if !os(macOS)
//    let horizontalSizeClass = UserInterfaceSizeClass.regular
//    #else
//    let horizontalSizeClass = UserInterfaceSizeClass.compact
//    #endif
//
//    @ViewBuilder var content: () -> Content
//
//    var currentLayout: AnyLayout {
//        if alignFirstTextLeadingIfHStack {
//            return horizontalSizeClass == .regular ? AnyLayout(HStackLayout(alignment: .firstTextBaseline)) : AnyLayout(VStackLayout())
//        }
//        else {
//            return horizontalSizeClass == .regular ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
//        }
//    }
//
//    var body: some View {
//        currentLayout(content)
//    }
//}

