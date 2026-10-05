//
//  InflectedString.swift
//  Salty
//
//  Plain text with Foundation's automatic grammar agreement applied, for places that need a `String`
//  rather than a SwiftUI `Text` (alerts, row subtitles built in a model, log-free status lines).
//

import Foundation

extension String {
    /// `value` localized, with `^[3 item](inflect: true)` markup agreed ("3 items") and then removed.
    ///
    /// `String(localized:)` leaves that markup in the text; only `AttributedString(localized:)` applies
    /// it, so this goes through one and keeps the characters.
    init(inflected value: String.LocalizationValue) {
        self = String(AttributedString(localized: value).characters)
    }
}
