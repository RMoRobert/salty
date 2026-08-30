//
//  SplitRecipesView.swift
//  Salty
//
//  Review screen for the "this file contains multiple recipes" PDF import. Shows each page and lets the
//  user mark where a new recipe begins (defaulting to one recipe per page); contiguous pages between
//  markers become one recipe. On confirm, the page groups are parsed and handed back via `onCreate`.
//

import SwiftUI
import CoreGraphics
import SaltyCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SplitRecipesView: View {
    let pageTexts: [String]
    let pageImages: [CGImage]
    let onCreate: ([Recipe]) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Page indices (besides 0) that begin a new recipe.
    @State private var startPages: Set<Int>

    init(pageTexts: [String], pageImages: [CGImage], onCreate: @escaping ([Recipe]) -> Void) {
        self.pageTexts = pageTexts
        self.pageImages = pageImages
        self.onCreate = onCreate
        // Default guess: every page begins a new recipe (the most common multi-recipe scan layout).
        _startPages = State(initialValue: Set(0..<pageTexts.count))
    }

    private var groups: [[Int]] {
        RecipePageSplitter.groups(pageCount: pageTexts.count, startPages: startPages)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tap a page to mark where a new recipe begins. Pages between markers become one recipe.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    Section("Recipe \(index + 1)") {
                        ForEach(group, id: \.self) { pageIndex in
                            pageRow(pageIndex)
                        }
                    }
                }
            }
            .navigationTitle("Split into Recipes")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create \(groups.count) Recipe\(groups.count == 1 ? "" : "s")") {
                        onCreate(RecipePageSplitter.recipes(pageTexts: pageTexts, startPages: startPages))
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pageRow(_ pageIndex: Int) -> some View {
        if pageIndex == 0 {
            // Page 1 always begins the first recipe — no toggle.
            rowContent(pageIndex, isStart: true)
        } else {
            Button {
                toggle(pageIndex)
            } label: {
                rowContent(pageIndex, isStart: startPages.contains(pageIndex))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func rowContent(_ pageIndex: Int, isStart: Bool) -> some View {
        HStack(spacing: 12) {
            thumbnail(pageIndex)
                .frame(width: 40, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Page \(pageIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(firstLine(pageTexts[pageIndex]))
                    .font(.callout)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: pageIndex == 0 ? "flag.fill" : (isStart ? "scissors.circle.fill" : "arrow.turn.down.right"))
                .imageScale(.large)
                .foregroundStyle(isStart ? Color.accentColor : .secondary)
                .accessibilityLabel(pageIndex == 0 ? "Recipe 1 starts here"
                                    : (isStart ? "New recipe starts here" : "Continues previous recipe"))
        }
        .contentShape(Rectangle())
    }

    private func toggle(_ pageIndex: Int) {
        if startPages.contains(pageIndex) {
            startPages.remove(pageIndex)
        } else {
            startPages.insert(pageIndex)
        }
    }

    private func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? "(no text recognized)"
    }

    @ViewBuilder
    private func thumbnail(_ pageIndex: Int) -> some View {
        if pageImages.indices.contains(pageIndex) {
            platformImage(pageImages[pageIndex])
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.secondary.opacity(0.1)
        }
    }

    private func platformImage(_ cgImage: CGImage) -> Image {
#if os(iOS)
        Image(uiImage: UIImage(cgImage: cgImage))
#elseif os(macOS)
        Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
#else
        Image(systemName: "doc")
#endif
    }
}
