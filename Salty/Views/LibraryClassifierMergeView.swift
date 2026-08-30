//
//  LibraryClassifierMergeView.swift
//  Salty
//  Created by Robert 8/19/2026
//
//  The confirmation sheet behind Merge in LibraryClassifiersEditView: fold several categories,
//  courses, or tags into one. Main function is to ask user which to keep and merge others into.
//

import SwiftUI
import SaltyCore

struct LibraryClassifierMergeView: View {
    let classifier: LibraryClassifier
    /// Every row being merged, survivor included, in survivor order.
    let candidates: [LibraryClassifierItem]
    @Binding var survivorID: String?
    let merge: () -> Void
    let cancel: () -> Void

    private var title: String {
        LibraryClassifiersEditViewModel.mergeTitle(for: candidates, classifier: classifier)
    }

    /// Recomputed here rather than handed in, so it tracks the picker as the survivor changes.
    private var message: String {
        LibraryClassifiersEditViewModel.mergeMessage(
            for: candidates,
            survivorID: survivorID,
            classifier: classifier
        )
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding([.horizontal, .top])
            picker
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Merge", action: merge)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(survivorID == nil)
            }
            .padding()
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320)
        #else
        NavigationStack {
            picker
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel, action: cancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Merge", action: merge)
                            .disabled(survivorID == nil)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        #endif
    }

    private var picker: some View {
        Form {
            Section {
                ForEach(candidates) { item in
                    LibraryClassifierMergeCandidateRow(
                        item: item,
                        isSurvivor: item.id == survivorID
                    ) {
                        survivorID = item.id
                    }
                }
            } header: {
                Text("\(classifier.singularLabel.capitalized) to keep")
            } footer: {
                Text(message)
            }
        }
        .formStyle(.grouped)
    }
}

/// One choosable row: the name, how many recipes use it, and whether it is the one being kept.
private struct LibraryClassifierMergeCandidateRow: View {
    let item: LibraryClassifierItem
    let isSurvivor: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                Image(systemName: isSurvivor ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSurvivor ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .imageScale(.large)
                Text(item.name)
                Spacer(minLength: 12)
                Text(item.recipeCount, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.recipeCount == 1 ? "\(item.name), 1 recipe" : "\(item.name), \(item.recipeCount) recipes")
        .accessibilityAddTraits(isSurvivor ? [.isSelected] : [])
    }
}

#Preview("Two categories") {
    @Previewable @State var survivorID: String? = "1"
    LibraryClassifierMergeView(
        classifier: .category,
        candidates: [
            LibraryClassifierItem(id: "1", name: "Desserts", recipeCount: 12),
            LibraryClassifierItem(id: "2", name: "Deserts", recipeCount: 3)
        ],
        survivorID: $survivorID,
        merge: {},
        cancel: {}
    )
}

#Preview("Several tags") {
    @Previewable @State var survivorID: String? = "1"
    LibraryClassifierMergeView(
        classifier: .tag,
        candidates: [
            LibraryClassifierItem(id: "1", name: "quick", recipeCount: 20),
            LibraryClassifierItem(id: "2", name: "Quick", recipeCount: 4),
            LibraryClassifierItem(id: "3", name: "fast", recipeCount: 2),
            LibraryClassifierItem(id: "4", name: "speedy", recipeCount: 1)
        ],
        survivorID: $survivorID,
        merge: {},
        cancel: {}
    )
}
