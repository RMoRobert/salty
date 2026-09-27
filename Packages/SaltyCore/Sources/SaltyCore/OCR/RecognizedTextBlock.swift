//
//  RecognizedTextBlock.swift
//  SaltyCore
//
//  One block of recognised text and where it sits on the page, built by the app from Vision
//  observations. Free of Vision types so ReadingOrderAssembler can be tested with synthetic layouts.
//

import Foundation

public struct RecognizedTextBlock: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case title
        case paragraph
        case listItem
        case tableRow
    }

    public var kind: Kind
    /// The block's text, one entry per recognised line (a wrapped paragraph has several).
    public var lines: [String]
    /// Normalised frame with the origin at the page's top-left corner; every value lies in 0...1.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(kind: Kind = .paragraph, lines: [String], x: Double, y: Double, width: Double, height: Double) {
        self.kind = kind
        self.lines = lines
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// The lines joined with newlines, as Vision's own transcript would be.
    public var transcript: String { lines.joined(separator: "\n") }
}
