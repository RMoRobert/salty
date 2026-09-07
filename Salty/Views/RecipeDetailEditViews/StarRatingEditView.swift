//
//  StarRatingEditView.swift
//  Salty
//
//  Created by Robert 9/6/26
//

import SwiftUI
import SaltyCore

/// An interactive five-star rating control, in the style of star widgets on the web.
///
/// Click or tap a star to set the rating, or drag across the row to sweep through
/// values. A clear button appears once a rating is set. On macOS, hovering previews
/// the rating a click would apply.
struct StarRatingEditView: View {
    @Binding var rating: Rating

    /// Sizes the stars
    var font: Font = .title3

    /// Which side the clear ("X") button sits on. Put it on the side *away* from the edge
    /// the surrounding layout aligns to, so the stars stay flush with neighbouring
    /// content: leading in a trailing-aligned Form row, trailing in a leading-aligned
    /// column.
    var clearButtonEdge: HorizontalEdge = .trailing

    @FocusState private var isFocused: Bool
    /// Whether the current focus came from a click rather than the keyboard, used to
    /// avoid a visible focus ring on macOS if not reached via the keyboard.
    @State private var focusedByPointer = false

    var body: some View {
        HStack {
            if clearButtonEdge == .leading {
                RatingClearButton(rating: $rating, edge: .leading)
            }

            RatingStarRow(rating: $rating) {
                // Guarded: the sweep reports this on every drag event.
                if !focusedByPointer {
                    focusedByPointer = true
                }
            }
            .font(font)

            if clearButtonEdge == .trailing {
                RatingClearButton(rating: $rating, edge: .trailing)
            }
        }
        #if os(macOS)
        // Mac only since long press interferes with actual rating on iOS
        .contextMenu {
            Button("Clear Rating", systemImage: "xmark.circle") {
                rating = .notSet
            }
            .disabled(rating == .notSet)
        }
        #endif
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(focusedByPointer)
        .onKeyPress(action: handleKeyPress)
        .onChange(of: isFocused) {
            // Next time focus arrives, assume the keyboard until a click says otherwise.
            if !isFocused {
                focusedByPointer = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == .notSet ? "Not set" : "\(rating.rawValue) of 5 stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = rating.stepped(by: 1)
            case .decrement: rating = rating.stepped(by: -1)
            @unknown default: break
            }
        }
        // The clear button and context menu are folded into this one element above, so
        // offer clearing as a named action rather than losing it to assistive tech.
        .accessibilityActions {
            if rating != .notSet {
                Button("Clear rating") {
                    rating = .notSet
                }
            }
        }
    }

    /// Arrow keys step the rating, 0-5 set it outright, delete clears it. Only reached
    /// while the control has keyboard focus; `onKeyPress` never sees keys otherwise.
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // Leave chorded shortcuts (⌘1, ⌥3, ...) to the app's menus and commands.
        guard keyPress.modifiers.isDisjoint(with: [.command, .control, .option]) else {
            return .ignored
        }

        // Consider keyboard in use now even if wasn't before
        focusedByPointer = false

        switch keyPress.key {
        case .leftArrow, .downArrow:
            rating = rating.stepped(by: -1)
        case .rightArrow, .upArrow:
            rating = rating.stepped(by: 1)
        case .delete, .deleteForward:
            rating = .notSet
        default:
            guard let digit = keyPress.characters.first?.wholeNumberValue,
                  let typed = Rating(rawValue: digit) else {
                return .ignored
            }
            rating = typed
        }

        return .handled
    }
}

private extension Rating {
    /// The rating `delta` steps away, clamped to the `notSet`...`five` range.
    func stepped(by delta: Int) -> Rating {
        let last = Self.allCases.count - 1
        return Rating(rawValue: Swift.min(Swift.max(rawValue + delta, 0), last)) ?? self
    }
}

// MARK: - Tap targets

/// The smallest comfortable touch target per HIG. Hit regions below are grown to
/// this size around glyphs that draw much smaller, without changing their layout.
/// Pointers are precise enough that macOS gets no such slop.
private enum TapTarget {
    #if os(iOS)
    static let minimum: CGFloat = 44
    #else
    static let minimum: CGFloat = 0
    #endif

    /// How much to add to each side of `length` to reach the minimum, never negative.
    static func slop(around length: CGFloat) -> CGFloat {
        max(0, (minimum - length) / 2)
    }
}

// MARK: - Clear button

/// Resets the rating to `.notSet`. Hidden rather than removed when there is nothing
/// to clear, so the stars do not shift as it comes and goes.
private struct RatingClearButton: View {
    @Binding var rating: Rating
    /// Which side of the stars this sits on, so the hit area can grow away from them.
    let edge: HorizontalEdge

    /// Measured glyph size, from which the hit slop is derived.
    @State private var glyphSize: CGSize = .zero

    var body: some View {
        Button("Clear rating", systemImage: "xmark.circle.fill") {
            rating = .notSet
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .help("Clear rating")
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            glyphSize = size
        }
        // Pad out, claim the padded area as the hit region, then take the padding back
        // out of the layout -- give enough room to tap without overly enlarging view
        .padding(hitSlop)
        .contentShape(.rect)
        .padding(hitSlop.negated)
        .opacity(rating == .notSet ? 0 : 1)
        .disabled(rating == .notSet)
        .animation(.default, value: rating == .notSet)
    }

    /// Grows entirely away from the stars: growing towards them would overlap the
    /// sweep's hit area and steal taps from the outermost star.
    private var hitSlop: EdgeInsets {
        let vertical = TapTarget.slop(around: glyphSize.height)
        let away = TapTarget.slop(around: glyphSize.width) * 2

        return switch edge {
        case .leading:
            EdgeInsets(top: vertical, leading: away, bottom: vertical, trailing: 0)
        case .trailing:
            EdgeInsets(top: vertical, leading: 0, bottom: vertical, trailing: away)
        }
    }
}

private extension EdgeInsets {
    var negated: EdgeInsets {
        EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing)
    }
}

// MARK: - Star row

/// The row of five stars, handling clicks, taps, hover previews and drag-to-sweep.
private struct RatingStarRow: View {
    @Binding var rating: Rating
    /// Called when a click or touch lands on the row, so the container can tell
    /// pointer-driven focus from keyboard focus.
    let onPointerDown: () -> Void

    /// The star a drag is currently over. Takes priority over `hoverRating`.
    /// Gesture state rather than plain state so that a drag which gets interrupted --
    /// by a scroll steal, a system gesture, a menu -- resets it; `onEnded` never runs
    /// for those, which would otherwise strand the preview fill on screen.
    @GestureState private var dragRating: Rating?
    /// The star the pointer is hovering over. macOS only -- see `onContinuousHover`.
    @State private var hoverRating: Rating?
    /// Size of the row, used to map a pointer location onto a star and to size the
    /// touch slop.
    @State private var rowSize: CGSize = .zero
    /// Per-star bounce triggers. Only the star a commit lands on has its count bumped,
    /// so only that star bounces; the ones already filled sit still.
    @State private var bounces: [Rating: Int] = [:]

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stars: [Rating] = [.one, .two, .three, .four, .five]
    private static let coordinateSpace = "StarRatingRow"

    #if os(iOS)
    /// Default spacing: each star's share of the row is its hit target, so the wider
    /// gap gets the targets closer to `TapTarget.minimum` without adding any height.
    private static let starSpacing: CGFloat? = nil
    #else
    /// Tight, to match the read-only `RatingView`.
    private static let starSpacing: CGFloat? = 2
    #endif

    /// The value to draw: a live preview when there is one, otherwise the real rating.
    private var previewRating: Rating? {
        dragRating ?? hoverRating
    }

    private var displayedRating: Rating {
        previewRating ?? rating
    }

    /// The sweep across the row. A drag here used to beat the enclosing Form's
    /// scroll outright, so touch scrolling on iOS by touching here would set rating
    /// instead of scroll. Two things fix that: the gesture is attached as *simultaneous*, so
    /// the scroll can recognise alongside it and take over vertical movement, and
    /// the sweep only previews or commits while the drag is mostly horizontal, so
    /// even a drag the scroll does not cancel leaves the rating alone.
    private var sweep: some Gesture {
        DragGesture(coordinateSpace: .named(Self.coordinateSpace))
            .updating($dragRating) { value, dragRating, _ in
                dragRating = Self.isSweeping(value) ? star(atX: value.location.x) : nil
            }
            .onChanged { _ in
                onPointerDown()
            }
            .onEnded { value in
                guard Self.isSweeping(value) else { return }
                rating = star(atX: value.location.x)
            }
    }

    /// Whether a drag reads as a sweep along the stars rather than a scroll past them.
    private static func isSweeping(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) >= abs(value.translation.height)
    }

    /// A plain tap, which the thresholded sweep no longer covers. Row-level rather
    /// than per-star buttons: buttons plus a drag made SwiftUI arbitrate between the
    /// two, and the button under the touch-down point always won.
    private var tap: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.coordinateSpace))
            .onEnded { value in
                onPointerDown()
                rating = star(atX: value.location.x)
            }
    }

    var body: some View {
        HStack(spacing: Self.starSpacing) {
            ForEach(Self.stars) { star in
                RatingStar(
                    isFilled: displayedRating.rawValue >= star.rawValue,
                    isPreview: previewRating != nil
                )
                // Twice the stock speed: a quick nod, not a full hop.
                .symbolEffect(.bounce, options: .speed(2), value: bounces[star, default: 0])
                .help(star.rawValue == 1 ? "1 star" : "\(star.rawValue) stars")
            }
        }
        .coordinateSpace(.named(Self.coordinateSpace))
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            rowSize = size
        }
        // Pad, claim the padded area as the hit region, then take the padding back
        // out of the layout -- generous touch slop that costs no row height.
        .padding(.vertical, touchSlop)
        .contentShape(.rect)
        .padding(.vertical, -touchSlop)
        // The sweep gets first claim; only when it fails (no movement) does the tap fire.
        // Simultaneous so the Form's scroll is never locked out; see `sweep`.
        .simultaneousGesture(sweep.exclusively(before: tap))
        #if os(macOS)
        // Row-level rather than per-star: hovering a star's own frame left the 2pt
        // gaps between them uncovered, so the preview dropped back to the real
        // rating every time the pointer crossed one. This maps the pointer the same
        // way the drag does, so there are no gaps.
        .onContinuousHover(coordinateSpace: .named(Self.coordinateSpace)) { phase in
            switch phase {
            case .active(let location): hoverRating = star(atX: location.x)
            case .ended: hoverRating = nil
            }
        }
        #endif
        // Ticks once per star crossed during a sweep, which is what makes the
        // gesture feel like a physical detent rather than a slider.
        .sensoryFeedback(.selection, trigger: displayedRating)
        // Commit feedback: on macOS the hover preview already shows the fill, so a
        // click on its own barely changes anything visible. Keyed to the real rating,
        // never the preview, so hover and sweep stay still. Clearing leaves empty
        // outlines, which look odd bouncing, so it gets none.
        .onChange(of: rating) {
            guard rating != .notSet, !reduceMotion else { return }
            bounces[rating, default: 0] += 1
        }
    }

    /// Extra touch area above and below the glyphs, which draw far shorter than a
    /// comfortable target.
    private var touchSlop: CGFloat {
        TapTarget.slop(around: rowSize.height)
    }

    /// Maps a horizontal position within the row onto the star it falls on.
    private func star(atX x: CGFloat) -> Rating {
        guard rowSize.width > 0 else { return rating }

        let ratio = x / rowSize.width
        let fraction = layoutDirection == .rightToLeft ? 1 - ratio : ratio
        let slot = Int(fraction * CGFloat(Self.stars.count))
        return Self.stars[min(max(slot, 0), Self.stars.count - 1)]
    }
}

// MARK: - Star

/// A single star, matching the fill and contrast treatment used by `RatingView`.
private struct RatingStar: View {
    let isFilled: Bool
    /// Hover and drag previews draw slightly faded so they read as provisional.
    let isPreview: Bool

    var body: some View {
        // The outline is drawn permanently and only the fill behind it fades in and
        // out. Swapping `star` for `star.fill` -- whether by symbol effect or by
        // cross-fade -- morphs between two different shapes, and the overlap partway
        // through is what made the change read as a wobble.
        Image(systemName: "star")
            .foregroundStyle(isFilled ? Color.ratingStarOutline : Color.secondary)
            // `ratingStarOutline` is transparent except under Increase Contrast in
            // light mode, where the outline -- not the fill -- carries the star's
            // contrast. Everywhere else a filled star shows only its fill.
            .background {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.ratingStar)
                    .opacity(fillOpacity)
            }
            .animation(.easeOut(duration: 0.1), value: isFilled)
    }

    private var fillOpacity: Double {
        guard isFilled else { return 0 }
        return isPreview ? 0.7 : 1
    }
}

#Preview("Star rating") {
    @Previewable @State var trailing = Rating.three
    @Previewable @State var leading = Rating.four
    @Previewable @State var empty = Rating.notSet

    Form {
        LabeledContent("Trailing clear") {
            StarRatingEditView(rating: $trailing)
        }
        LabeledContent("Leading clear") {
            StarRatingEditView(rating: $leading, clearButtonEdge: .leading)
        }
        LabeledContent("Not set") {
            StarRatingEditView(rating: $empty, clearButtonEdge: .leading)
        }
        LabeledContent("Compact") {
            StarRatingEditView(rating: $trailing, font: .body)
        }
    }
    .padding()
}
