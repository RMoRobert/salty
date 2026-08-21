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
    let isLoading: Bool
    /// Computed from the window width by the caller: the toolbar grants a principal item exactly its
    /// ideal width (measured -- `maxWidth` is never consulted), so elasticity has to come from the
    /// ideal itself tracking the space available.
    let idealWidth: CGFloat
    let onSubmit: () -> Void
    let onReloadOrStop: () -> Void

    var body: some View {
        AddressFieldRepresentable(text: $text, isLoading: isLoading, onSubmit: onSubmit)
            .frame(minWidth: 200, idealWidth: idealWidth, maxWidth: .infinity)
            // Reload sits inside the field's trailing edge, Safari-style. It can overlay the bezel
            // safely because the cell insets the text's drawing rect to keep the URL from running
            // underneath it -- see `AddressFieldCell`.
            .overlay(alignment: .trailing) {
                // Loading feedback lives inside the field, per Safari, whose spinner (and now its
                // progress sweep) has always been part of the address bar. Spinner to the left of
                // Stop, so the cancel control keeps the outermost spot.
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button(isLoading ? "Stop" : "Reload",
                           systemImage: isLoading ? "xmark" : "arrow.clockwise",
                           action: onReloadOrStop)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut("r", modifiers: .command)
                        .help(isLoading ? "Stop loading this page" : "Reload this page")
                }
                .padding(.trailing, 8)
            }
            // Headroom for the focus ring, which AppKit draws *outside* the control's bounds -- a
            // ~3pt stroke plus a soft glow, so 4pt all round left the ring visibly flattened top and
            // bottom. More vertically than horizontally because the ring's ends have the bezel's own
            // capsule radius to spread into, while its edges have nothing.
            // Enough for the focus ring (which draws outside the control) without inflating the
            // item -- at 6pt the field's glass pod stood taller than the row's other pods.
            .padding(.vertical, 3)
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
    let isLoading: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> AddressTextField {
        let field = AddressTextField()
        field.placeholderString = "Enter URL"
        field.bezelStyle = .roundedBezel
        // Regular, not large: in the unified toolbar the field shares a row with standard-height
        // buttons, and the large bezel stood awkwardly taller than everything beside it. (Large was
        // a fix for selection-highlight clipping in the SwiftUI-hosted era; the owned field sizes
        // its editor from its own metrics, so regular should hold -- watch for that regressing.)
        field.controlSize = .regular
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular))
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
        field.fullURL = text
        // Room for Stop alone, or spinner + Stop while loading.
        field.trailingInset = isLoading ? 46 : 24
        if field.currentEditor() == nil {
            // Idle: styled display (scheme hidden, domain emphasised). Unconditional rather than
            // diffed, because `stringValue` holds the *display* text while idle and so never
            // compares equal to the full URL.
            field.applyIdleDisplay()
        } else if field.stringValue != text {
            // Editing: plain text only, and only if navigation changed the URL out from under it.
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
            (field as? AddressTextField)?.fullURL = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            // Editing over -- swap the plain URL back out for the styled idle display.
            (notification.object as? AddressTextField)?.applyIdleDisplay()
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
    /// The canonical URL, always complete with scheme. `stringValue` can't serve as this while the
    /// field is idle, because idle display is the styled, scheme-stripped form.
    var fullURL: String = ""

    /// How far the text stops short of the trailing edge; grows while the spinner accompanies the
    /// Stop button. Read by `AddressFieldCell`.
    var trailingInset: CGFloat = 24 {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    /// I-beam only over the text; the trailing strip holds the inline Reload/Stop (and spinner), and
    /// a button under an I-beam reads as untargetable. NSTextField's default is I-beam wall to wall.
    override func resetCursorRects() {
        var textRect = bounds
        textRect.size.width = max(0, textRect.size.width - trailingInset)
        addCursorRect(textRect, cursor: .iBeam)

        var controlsRect = bounds
        controlsRect.origin.x = textRect.maxX
        controlsRect.size.width = bounds.width - textRect.width
        addCursorRect(controlsRect, cursor: .arrow)
    }

    override class var cellClass: AnyClass? {
        get { AddressFieldCell.self }
        set {}
    }

    /// The idle look borrowed from modern browser address bars: scheme hidden, domain in the primary
    /// label colour, the rest of the URL secondary. Editing always works on the plain, complete URL
    /// -- `becomeFirstResponder` swaps it in before the field editor takes over.
    func applyIdleDisplay() {
        let display = fullURL.hasPrefix("https://") ? String(fullURL.dropFirst(8))
                    : fullURL.hasPrefix("http://") ? String(fullURL.dropFirst(7))
                    : fullURL

        // Truncation must ride along in the paragraph style: an attributed value overrides the
        // cell's own line-break mode.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let styled = NSMutableAttributedString(string: display, attributes: [
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])

        // Only a URL with a real host gets the domain/rest split; "about:home" and friends stay
        // uniformly primary.
        if let host = URLComponents(string: fullURL)?.host,
           let hostRange = display.range(of: host) {
            styled.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                range: NSRange(display.startIndex..<display.endIndex, in: display))
            styled.addAttribute(.foregroundColor, value: NSColor.labelColor,
                                range: NSRange(hostRange, in: display))
        }
        attributedStringValue = styled
    }

    override func becomeFirstResponder() -> Bool {
        // The field editor must take over the plain, complete URL, not the styled display -- this is
        // also what brings the hidden scheme back for editing.
        stringValue = fullURL
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

/// Insets the text's drawing (and therefore editing) rect from the trailing edge, so the URL stops
/// short of the inline Reload button that SwiftUI overlays on the field. The bezel itself still
/// draws across the full bounds -- only the text is narrowed.
private final class AddressFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var inset = super.drawingRect(forBounds: rect)
        inset.size.width -= (controlView as? AddressTextField)?.trailingInset ?? 24
        return inset
    }
}
#endif
