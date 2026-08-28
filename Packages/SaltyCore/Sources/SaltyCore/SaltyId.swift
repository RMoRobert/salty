//
//  SaltyId.swift
//  SaltyCore
//
//  Row identifiers, in the exact textual shape every Salty client produces.
//

import Foundation
import UUIDV7

/// Mints and normalises row ids.
///
/// Ids are stored as TEXT and compared as plain strings — no column carries a case-insensitive
/// collation — so casing is significant everywhere. Swift's `UUID.uuidString` is uppercase, which is
/// what makes uppercase the canonical form; .NET's `Guid.ToString()` is lowercase and has to be
/// upper-cased on that side.
///
/// UUIDv7 rather than v4 for the time-ordered prefix. Existing libraries hold a mix and nothing depends
/// on the version, so it affects only rows a client creates.
public enum SaltyId {

    /// A new uppercase, hyphenated UUIDv7 string.
    public static func new() -> String {
        UUIDV7().uuidString
    }

    /// Normalises an id that arrived from outside — an import, a wire payload — into canonical form.
    /// Anything that is not a canonical-form UUID passes through **untouched**: these columns are plain
    /// TEXT and no client may start rejecting ids its peers accept.
    ///
    /// Defensive, not load-bearing. No path in Salty currently feeds it a foreign id: `.saltyRecipe`
    /// import mints fresh ids for the recipe and every nested item, and wire ids originate from a client
    /// that already produced them in this shape. It exists so that a future import path which *does*
    /// preserve ids cannot introduce a casing mismatch. See ID-004 in `salty-contract/SPEC.md`.
    ///
    /// Only the hyphenated 8-4-4-4-12 form is recognised, matching `UUID(uuidString:)`. A bare 32-digit
    /// hex string is NOT a UUID here, so that all three clients agree on what counts.
    public static func normalize(_ id: String) -> String {
        UUID(uuidString: id).map(\.uuidString) ?? id
    }
}
