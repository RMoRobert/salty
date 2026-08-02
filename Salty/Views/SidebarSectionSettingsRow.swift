//
//  SidebarSectionSettingsRow.swift
//  Salty
//
//  Controls for the reorderable sidebar sections, shared by General settings and the Sidebar Items menu.
//

import SwiftUI

/// Show/hide toggle for one sidebar section. Keeps its own `@AppStorage` mirror so the control refreshes
/// wherever it's used, and writes through `SidebarSectionOrder` so the "at least one of Categories,
/// Courses, or Tags" rule is enforced in one place. Apply `.labelsHidden()` where the row supplies its
/// own label.
struct SidebarSectionVisibilityToggle: View {
    let section: SidebarSection
    @AppStorage private var isVisible: Bool

    init(section: SidebarSection) {
        self.section = section
        _isVisible = AppStorage(wrappedValue: true, section.visibilityKey)
    }

    var body: some View {
        Toggle("Show \(section.displayName)", isOn: Binding(
            get: { isVisible },
            // Refused changes (the last of the required three) simply don't stick, matching how the
            // search-options toggles behave.
            set: { SidebarSectionOrder.setVisible($0, for: section) }
        ))
    }
}

/// One row of the reorderable list in General settings: the section's name, arrows to move it, and its
/// show/hide switch. The arrows are the only way to reorder on macOS, where a grouped Form ignores
/// `onMove`; on iOS a row can also be dragged.
struct SidebarSectionSettingsRow: View {
    let section: SidebarSection
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    @AppStorage private var isVisible: Bool

    init(section: SidebarSection, canMoveUp: Bool, canMoveDown: Bool, move: @escaping (Int) -> Void) {
        self.section = section
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.move = move
        _isVisible = AppStorage(wrappedValue: true, section.visibilityKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(section.displayName, systemImage: section.systemImage)
                // A hidden section still keeps its place in the order, so it stays in the list -- dimmed
                // rather than removed.
                .foregroundStyle(isVisible ? .primary : .secondary)
            Spacer()
            Button {
                move(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(!canMoveUp)
            .accessibilityLabel("Move \(section.displayName) Up")

            Button {
                move(1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(!canMoveDown)
            .accessibilityLabel("Move \(section.displayName) Down")

            SidebarSectionVisibilityToggle(section: section)
                .labelsHidden()
        }
        // Several controls share this row, so on iOS each needs its own hit area rather than the
        // whole-row tap a Form gives a lone button.
        .buttonStyle(.borderless)
    }
}
