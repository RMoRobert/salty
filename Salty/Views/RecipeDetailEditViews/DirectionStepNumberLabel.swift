//
//  DirectionStepNumberLabel.swift
//  Salty
//
//  The step number beside a direction row in the mobile editor.
//

import SwiftUI

/// Drawn by a read-only `TextField` rather than a `Text`: SwiftUI puts a `Text`'s baseline a
/// fraction of a point above where a vertical-axis `TextField` draws its first line, which is a
/// whole device pixel on 2x screens. The hidden `Text` supplies the width a `TextField` lacks.
struct DirectionStepNumberLabel: View {
    let number: Int

    private var label: String { "\(number.formatted())." }

    var body: some View {
        Text(label)
            .hidden()
            .overlay(alignment: .trailing) {
                TextField("", text: .constant(label), axis: .vertical)
                    .disabled(true)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}

#Preview {
    List {
        ForEach([1, 2, 12], id: \.self) { number in
            HStack(alignment: .top) {
                DirectionStepNumberLabel(number: number)
                TextField("Direction Text", text: .constant("Combine all ingredients and mix well."), axis: .vertical)
            }
        }
    }
}
