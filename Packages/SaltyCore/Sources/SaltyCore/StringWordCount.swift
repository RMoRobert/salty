//
//  StringWordCount.swift
//  SaltyCore
//
//  Word counting for the plain-text recipe parser.
//
//  RecipeFromTextParser used to reach for `NLTokenizer(unit: .word)` here. The tokenizer was doing
//  nothing that justified the NaturalLanguage dependency: its single surviving use was a word count
//  feeding a coarse "does this line look like a title?" test (2...15 words). Unicode scalar
//  classification answers that identically for recipe text.
//

import Foundation

public extension String {
    /// Number of whitespace-delimited words, ignoring runs of punctuation.
    ///
    /// `"1/2 cup sugar"` is 3 words, `"Grandma's  Apple  Pie"` is 3, `"---"` is 0.
    var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace })
            .count { token in token.contains { $0.isLetter || $0.isNumber } }
    }
}
