//
//  ChefViewTextSizePopover.swift
//  Salty
//
//  Chef View's text-size control: a discrete slider between a small and a large A, the same shape
//  as the system's own Display & Text Size control.
//
//  It's a slider because one drag crosses the whole range — reaching the largest sizes for a TV
//  across the room shouldn't take six taps. It's *discrete* (`step: 1`) because the sizes are a
//  fixed ladder of Dynamic Type steps, not a continuum; macOS draws tick marks for them. The two
//  A's are still buttons, so the control can be nudged a step at a time by tapping, without the
//  drag precision a bare slider would demand of messy hands.
//
//  It lives in a popover rather than inline in the header, so it gets a usable width even on an
//  iPhone, where the bar has no room to spare.
//

import SwiftUI

struct ChefViewTextSizePopover: View {
    @Binding var textSizeLevel: Int

    /// Slider works in Double; the stored setting is a step index.
    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(ChefViewTextSize.clamped(textSizeLevel)) },
            set: { textSizeLevel = Int($0.rounded()) }
        )
    }

    private var isAtMinimum: Bool { textSizeLevel <= ChefViewTextSize.minimumLevel }
    private var isAtMaximum: Bool { textSizeLevel >= ChefViewTextSize.maximumLevel }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text Size")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Smaller Text", systemImage: "textformat.size.smaller") {
                    textSizeLevel = max(ChefViewTextSize.minimumLevel, textSizeLevel - 1)
                }
                .disabled(isAtMinimum)

                Slider(
                    value: sliderValue,
                    in: Double(ChefViewTextSize.minimumLevel)...Double(ChefViewTextSize.maximumLevel),
                    step: 1
                )
                .accessibilityLabel("Text Size")
                .accessibilityValue(ChefViewTextSize.accessibilityValue(for: textSizeLevel))

                Button("Larger Text", systemImage: "textformat.size.larger") {
                    textSizeLevel = min(ChefViewTextSize.maximumLevel, textSizeLevel + 1)
                }
                .disabled(isAtMaximum)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .imageScale(.large)
        }
        // No "Text size 3 of 9" readout under the slider: the step number means nothing next to the
        // text it's setting, which is right there behind the popover and changes as you drag. The
        // same string is still announced by VoiceOver, where the slider position isn't visible.
        .padding()
        .frame(minWidth: 280)
        // The control sets its own size; it shouldn't grow with the size it's setting.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

#Preview {
    @Previewable @State var level = ChefViewTextSize.defaultLevel
    return ChefViewTextSizePopover(textSizeLevel: $level)
}
