//
//  RecipeRowEditorShell.swift
//  Salty
//
//  How the five recipe list editors are framed. Standing alone (a sheet, as the web importer opens
//  them) they get a title, their add buttons in the toolbar, a Done button and a sheet-sized frame.
//  Embedded in the recipe editor they take no frame and show the same add buttons beneath the list
//  when asked to.
//

import SwiftUI

struct RecipeRowEditorShell<Content: View, Actions: View>: View {
    let title: String
    let isStandalone: Bool
    /// Embedded only: whether the add buttons are drawn under the list.
    let showsBottomButtons: Bool
    @ViewBuilder let content: () -> Content
    /// The editor's add buttons, shown in the toolbar or under the list.
    @ViewBuilder let actions: () -> Actions

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if isStandalone {
            content()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        actions()
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                }
                .frame(minWidth: 600, idealWidth: 700, maxWidth: 800,
                       minHeight: 500, idealHeight: 600, maxHeight: 800)
                .presentationSizing(.fitted)
        } else {
            VStack(spacing: 0) {
                content()
                if showsBottomButtons {
                    HStack {
                        actions()
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
