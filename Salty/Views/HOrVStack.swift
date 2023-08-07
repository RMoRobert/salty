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
        if alignFirstTextLeadingIfHStack {
            return horizontalSizeClass == .regular ? AnyLayout(HStackLayout(alignment: .firstTextBaseline)) : AnyLayout(VStackLayout())
        }
        else {
            return horizontalSizeClass == .regular ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
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

