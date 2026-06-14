//
//  ErrorAlertViewExtension.swift
//  Salty
//  Created by Robert 6/14/26
//
//  A lightweight, reusable way to surface an operation failure to the user.
//  A view model exposes an optional message (`var operationError: String?`); set it in a
//  `catch` to present a one-button alert, and it clears itself on dismiss.
//

import SwiftUI

extension View {
    /// Presents a simple acknowledgement alert whenever `message` becomes non-nil,
    /// clearing the binding when dismissed.
    func errorAlert(_ message: Binding<String?>, title: String = "Something Went Wrong") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { presenting in if !presenting { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: { text in
            Text(text)
        }
    }
}
