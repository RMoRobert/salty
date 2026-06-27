//
//  AutoSyncFailureBanner.swift
//  Salty
//
//  Non-modal banner shown by `MainView` after automatic sync has failed several times in a row.
//  Deliberately unobtrusive: it sits at the top of the content, doesn't block interaction, and can be
//  dismissed or retried. Manual sync (Settings) remains the place to see the actual error detail.
//

import SwiftUI

struct AutoSyncFailureBanner: View {
    let onRetry: () -> Void
    let onDismiss: () -> Void
    let onPause: () -> Void

    /// Tracks an in-progress upward swipe so the banner follows the finger before dismissing.
    @State private var dragOffset: CGFloat = 0
    /// Guards against firing dismissal repeatedly while a swipe is still in progress.
    @State private var isDismissing = false

    /// How far up you must swipe to dismiss. Small on purpose: the banner sits beneath the (Liquid Glass)
    /// toolbar, which swallows drag events once the banner slides under it — so a long drag can't register.
    private let dismissThreshold: CGFloat = 12

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.large)
                .foregroundStyle(Color.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Server sync failed")
                    .font(.subheadline.weight(.semibold))
                Text("Recent changes were not able to be backed up to Salty Sever. Open app Settings to verify your configuration.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onPause) {
                    Text("Pause sync for 1 day")
                        .font(.caption.weight(.semibold))
                        .underline()
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
                .accessibilityHint("Stops automatic sync for 24 hours")
            }

            Spacer(minLength: 8)

            Button("Retry", action: onRetry)
                .bannerProminentButtonStyle()
                .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .padding(4)
            }
            .bannerPlainButtonStyle()
            .controlSize(.small)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow)
                .shadow(
                    color: Color.gray.opacity(0.7),
                    radius: 4,
                    x: 1,
                    y: 1
                )
        )
        // Tap anywhere (outside the Retry/X buttons) or swipe up to dismiss — the X alone is a small target.
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    guard !isDismissing else { return }
                    // Dismiss as soon as a slight upward swipe is detected, before the banner can slide
                    // up under the toolbar (which would steal the rest of the drag).
                    if value.translation.height < -dismissThreshold {
                        isDismissing = true
                        onDismiss()
                    } else {
                        dragOffset = min(0, value.translation.height) // follow upward drags only
                    }
                }
                .onEnded { _ in
                    if !isDismissing { withAnimation(.snappy) { dragOffset = 0 } }
                }
        )
        .onTapGesture { onDismiss() }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

private extension View {
    /// The accessory-bar styles are macOS-only; iOS falls back to standard equivalents so the shared
    /// banner compiles and looks reasonable on both platforms.
    @ViewBuilder func bannerProminentButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.accessoryBarAction)
        #else
        buttonStyle(.borderedProminent)
        #endif
    }

    @ViewBuilder func bannerPlainButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.accessoryBar)
        #else
        buttonStyle(.plain)
        #endif
    }
}

#Preview {
    AutoSyncFailureBanner(onRetry: {}, onDismiss: {}, onPause: {})
}
