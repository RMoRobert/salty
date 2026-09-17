//
//  StringWebLinks.swift
//  SaltyCore
//
//  Links web addresses inside text where entire text is not necessarily a URL, such as recipe
//  source details that say "Adapted from https://example.com/recipe". Needs HTTP or HTTPS protocol
//  specified; won't catch bare domain (but neither will whole-field detection, either).
//
//  Created by Robert 9/16/2026
//

import Foundation

public extension String {
    /// Converts text into text with HTTP or HTTPS addresses contained inside marked as a link
    var attributedWithWebLinks: AttributedString {
        var attributed = AttributedString(self)
        for match in matches(of: #/https?://[^\s<>"]+/#.ignoresCase()) {
            let address = match.output.droppingPunctuationOutsideUrl()
            guard let url = URL(string: String(address)), url.host() != nil,
                  let range = Range(address.startIndex..<address.endIndex, in: attributed) else {
                continue
            }
            attributed[range].link = url
        }
        return attributed
    }
}

private extension Substring {
    /// Removes sentence punctuation, closing quotes, and (unbalanced) closing brackets from end of URL string
    func droppingPunctuationOutsideUrl() -> Substring {
        var address = self
        while let last = address.last {
            let isProse = switch last {
            case ".", ",", ";", ":", "!", "?", "'", "’", "”": true
            case ")": address.count(where: { $0 == ")" }) > address.count(where: { $0 == "(" })
            case "]": address.count(where: { $0 == "]" }) > address.count(where: { $0 == "[" })
            default: false
            }
            guard isProse else { break }
            address = address.dropLast()
        }
        return address
    }
}
