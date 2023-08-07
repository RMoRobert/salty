//
//  HOrVStack.swift
//  Salty
//
//  Created by Robert on 7/28/23.
//

import SwiftUI

struct HOrVStack<Content: View>: View {
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
        horizontalSizeClass == .regular ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
    }

    var body: some View {
        currentLayout(content)
    }
}

