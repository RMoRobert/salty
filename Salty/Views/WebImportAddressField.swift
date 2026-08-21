//
//  WebImportAddressField.swift
//  Salty
//
//  Created by Robert on 8/19/26.
//

import SwiftUI

#if os(macOS)
import AppKit

/// The web import browser's address field: an `NSTextField` owned directly, rather than SwiftUI's
/// toolbar-hosted `TextField`.
///
/// Owning the field puts every focus behaviour in one reachable place, which the hosted field never
/// offered: `@FocusState` doesn't track toolbar content, `NSControl.textDidBeginEditingNotification`
/// was never posted for it, and the one signal that worked (KVO on the window's `firstResponder`)
/// meant a separate observer view reaching into a field it didn't own. Here `becomeFirstResponder`
/// *is* the focus signal -- select-all on focus arrival for clicks and ⌘L alike -- and the SwiftUI
/// hosting adaptor, the remaining suspect for the first-focus ring/highlight glitch, is gone.
///
/// The drawing is still all system: bezel (a capsule on macOS 26), focus ring, and selection
/// highlight are AppKit's. This wrapper contributes only the layout numbers, which keep their
/// measured values from the hosted version -- see the comments on each.
struct WebImportAddressField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        AddressFieldRepresentable(text: $text, onSubmit: onSubmit)
            // The toolbar sizes this to `idealWidth`, not `maxWidth` (measured -- the field came out
            // at exactly the old ideal), so widening means raising the ideal.
            .frame(minWidth: 200, idealWidth: 700, maxWidth: .infinity)
            // Headroom for the focus ring, which AppKit draws *outside* the control's bounds -- a
            // ~3pt stroke plus a soft glow, so 4pt all round left the ring visibly flattened top and
            // bottom. More vertically than horizontally because the ring's ends have the bezel's own
            // capsule radius to spread into, while its edges have nothing.
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
    }
}

extension WebImportAddressField {
    /// Moves keyboard focus to the key window's address field, for File ▸ Open Location (⌘L).
    ///
    /// Goes through AppKit because SwiftUI's `@FocusState` doesn't reach toolbar-hosted content:
    /// setting a binding leaves first responder where it was, verified by reading the accessibility
    /// focus before and after. Owning the field's class makes the lookup exact -- no heuristics
    /// about which editable text field is meant. Finds nothing, and so does nothing, at compact
    /// widths where the field isn't in the toolbar at all.
    @MainActor
    static func focusInKeyWindow() {
        guard let window = NSApp.keyWindow,
              let root = window.contentView?.superview,
              let field = firstView(ofType: AddressTextField.self, in: root)
        else { return }
        // Select-all comes with focus -- see `AddressTextField.becomeFirstResponder`.
        window.makeFirstResponder(field)
    }

    private static func firstView<V: NSView>(ofType type: V.Type, in view: NSView) -> V? {
        if let match = view as? V { return match }
        for subview in view.subviews {
            if let found = firstView(ofType: type, in: subview) { return found }
        }
        return nil
    }
}

/// The AppKit half of `WebImportAddressField`. Bridges text and Return in the conventional
/// coordinator shape; everything visual is the stock bezel field.
private struct AddressFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> AddressTextField {
        let field = AddressTextField()
        field.placeholderString = "Enter URL"
        field.bezelStyle = .roundedBezel
        field.controlSize = .large
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large))
        // Truncate idle URLs in the middle, Safari-style; the field editor scrolls while editing.
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingMiddle
        field.delegate = context.coordinator
        // A long URL must never dictate the toolbar's layout; width belongs to the wrapper's frame.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: AddressTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressFieldRepresentable

        init(_ parent: AddressFieldRepresentable) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            // Return commits the field and hands focus back to the page, as Safari's address bar does.
            control.window?.makeFirstResponder(nil)
            parent.onSubmit()
            return true
        }
    }
}

/// Selects the whole URL whenever the field takes focus, as Safari's address bar does. Overriding
/// `becomeFirstResponder` is the reason this control is owned at all: no equivalent hook exists for
/// a SwiftUI toolbar field.
private final class AddressTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        // Deferred into `.default` mode so the selection lands after the click that delivered focus:
        // AppKit tracks the mouse in a modal `.eventTracking` loop that sets the insertion point
        // from the click as it ends, undoing any selection made here directly -- and `.default`
        // mode isn't serviced until that loop is over. Keyboard focus (⌘L) has no tracking loop, so
        // for it this runs promptly and merely re-applies AppKit's own whole-contents selection.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.currentEditor()?.selectAll(nil)
            }
        }
        return true
    }
}
#endif
