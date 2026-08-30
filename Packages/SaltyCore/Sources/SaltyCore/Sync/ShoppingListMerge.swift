//
//  ShoppingListMerge.swift
//  Salty
//
//  Pure three-way merge for a shopping list that changed on BOTH sides since the last server
//  agreement (`base`, the stored `syncedSnapshot`). Mirrors RecipeSyncReconciler's design contract:
//  pure, I/O-free, data-loss-critical, exhaustively unit-tested — and it is a line-for-line port of
//  SaltyKMP's ShoppingListMerge.kt; keep the two in lockstep.
//
//  Resolution rules:
//   - Scalars (name, isFreeform): the side that changed vs base wins; both changed → newer
//     `lastModifiedDate` wins (clocks are only ever a tie-breaker, never the primary signal).
//   - Checklist items, keyed by their stable item ids: adds/edits/deletes on DIFFERENT items merge
//     silently; same-item edits merge field-level (text: newer side; completed/important: OR — a
//     checked-off or flagged item stays that way); a delete loses to an edit of the same item.
//     Item order: the server's order is the spine, local-only additions slot in after their nearest
//     surviving local predecessor.
//   - Freeform text (one opaque markdown blob) changed on both sides, or the two sides disagree on
//     isFreeform itself: no sensible auto-merge exists, so the newer side becomes `Resolution.merged`
//     and the other side is preserved WHOLE as `Resolution.conflictCopy` — a brand-new list the
//     caller inserts and uploads. Nothing is ever silently discarded.
//   - No base (legacy row, or an unreadable snapshot): two-way merge — same shape, but "changed vs
//     base" degrades to newer-wins per field, and item unions keep both sides' additions.
//
//  The merged list's `lastModifiedDate` is the newer of the two inputs; `revision`/`baseRevision`
//  are cleared — the caller stamps `baseRevision` when uploading.
//

import Foundation

public enum ShoppingListMerge {

    public struct Resolution {
        public let merged: ServerShoppingList
        /// Set only when a side couldn't be merged in (freeform/isFreeform conflicts): a NEW list
        /// (fresh `conflictCopyId`) preserving that side verbatim. Nil = clean merge.
        public let conflictCopy: ServerShoppingList?

        public init(merged: ServerShoppingList, conflictCopy: ServerShoppingList? = nil) {
            self.merged = merged
            self.conflictCopy = conflictCopy
        }
    }

    /// - Parameters:
    ///   - conflictCopyId: fresh id to use IF a conflict copy is needed (pure function — the caller
    ///     owns id generation).
    ///   - conflictCopyLabel: appended to the copy's name, e.g. "conflicted copy 2026-08-13".
    public static func resolve(
        base: ServerShoppingList?,
        local: ServerShoppingList,
        server: ServerShoppingList,
        conflictCopyId: String,
        conflictCopyLabel: String
    ) -> Resolution {
        let localIsNewer = dateOrPast(local.lastModifiedDate) > dateOrPast(server.lastModifiedDate)
        let newer = localIsNewer ? local : server
        let older = localIsNewer ? server : local
        let mergedDate = newer.lastModifiedDate

        func conflictCopy(of side: ServerShoppingList) -> ServerShoppingList {
            var copy = side
            copy.id = conflictCopyId
            copy.name = "\(side.name ?? "Shopping List") (\(conflictCopyLabel))"
            copy.revision = nil
            copy.baseRevision = nil
            return copy
        }

        // The two sides disagree on what KIND of list this is (one converted it to freeform):
        // structurally unmergeable — newer side wins, older side survives as a copy.
        let isFreeform = pick(base?.isFreeform.eff, local.isFreeform.eff, server.isFreeform.eff, localIsNewer: localIsNewer)
        if local.isFreeform.eff != server.isFreeform.eff {
            var merged = newer
            merged.revision = nil
            merged.baseRevision = nil
            return Resolution(merged: merged, conflictCopy: conflictCopy(of: older))
        }

        let name = pickOptional(base?.name, local.name, server.name, localIsNewer: localIsNewer)

        if isFreeform {
            let baseText = base?.contentsForFreeform
            let localText = local.contentsForFreeform
            let serverText = server.contentsForFreeform
            let bothChanged = base != nil &&
                localText != serverText && localText != baseText && serverText != baseText
            let bothChangedNoBase = base == nil && localText != serverText
            if bothChanged || bothChangedNoBase {
                var merged = server
                merged.name = name
                merged.lastModifiedDate = mergedDate
                merged.revision = nil
                merged.baseRevision = nil
                return Resolution(merged: merged, conflictCopy: conflictCopy(of: local))
            }
            return Resolution(
                merged: ServerShoppingList(
                    id: local.id,
                    name: name,
                    isFreeform: true,
                    contentsForList: nil,
                    contentsForFreeform: pickOptional(baseText, localText, serverText, localIsNewer: localIsNewer),
                    lastModifiedDate: mergedDate
                )
            )
        }

        return Resolution(
            merged: ServerShoppingList(
                id: local.id,
                name: name,
                isFreeform: false,
                contentsForList: mergeItems(
                    base: base?.contentsForList,
                    local: local.contentsForList ?? [],
                    server: server.contentsForList ?? [],
                    localIsNewer: localIsNewer
                ),
                contentsForFreeform: pickOptional(base?.contentsForFreeform, local.contentsForFreeform, server.contentsForFreeform, localIsNewer: localIsNewer),
                lastModifiedDate: mergedDate
            )
        )
    }

    /// Changed-side-wins for one scalar; both changed (or no base to tell) → newer side.
    private static func pick<T: Equatable>(_ baseValue: T?, _ localValue: T, _ serverValue: T, localIsNewer: Bool) -> T {
        if localValue == serverValue { return localValue }
        guard let baseValue else { return localIsNewer ? localValue : serverValue }
        if localValue == baseValue { return serverValue }
        if serverValue == baseValue { return localValue }
        return localIsNewer ? localValue : serverValue
    }

    /// The same rule for an OPTIONAL scalar. Split from `pick` because nesting optionals (T == U?)
    /// would let Swift's implicit promotion turn "no base row" into "base value present but nil" at
    /// the call site; here a nil `baseValue` means either — exactly how the Kotlin original's
    /// `base?.field` collapses the two.
    private static func pickOptional<T: Equatable>(_ baseValue: T?, _ localValue: T?, _ serverValue: T?, localIsNewer: Bool) -> T? {
        if localValue == serverValue { return localValue }
        guard let baseValue else { return localIsNewer ? localValue : serverValue }
        if localValue == baseValue { return serverValue }
        if serverValue == baseValue { return localValue }
        return localIsNewer ? localValue : serverValue
    }

    private static func mergeItems(
        base: [ShoppingListListContents]?,
        local: [ShoppingListListContents],
        server: [ShoppingListListContents],
        localIsNewer: Bool
    ) -> [ShoppingListListContents] {
        let baseById = Dictionary((base ?? []).map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localById = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let serverById = Dictionary(server.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let hasBase = base != nil

        // Server order is the spine.
        var result: [ShoppingListListContents] = []
        for s in server {
            let b = baseById[s.id]
            if let l = localById[s.id] {
                result.append(mergeItem(base: b, local: l, server: s, localIsNewer: localIsNewer))
            } else if !hasBase || b == nil {
                result.append(s)                      // new on the server (or no base to judge)
            } else if s != b {
                result.append(s)                      // local deleted it, but the server edited it since base → edit beats delete
            }
            // else: local deleted an unchanged item → deletion stands
        }

        // Local-only items slot in after their nearest local predecessor that survived the merge.
        for (index, l) in local.enumerated() {
            if serverById[l.id] != nil { continue }
            let b = baseById[l.id]
            let keep = !hasBase || b == nil || l != b // new locally, or edited since base (edit beats delete)
            if !keep { continue }
            var insertAt = 0
            for j in stride(from: index - 1, through: 0, by: -1) {
                if let anchor = result.firstIndex(where: { $0.id == local[j].id }) {
                    insertAt = anchor + 1
                    break
                }
            }
            result.insert(l, at: insertAt)
        }
        return result
    }

    /// Same item touched on both sides: field-level, so a check-off and a text edit both survive.
    private static func mergeItem(
        base: ShoppingListListContents?,
        local: ShoppingListListContents,
        server: ShoppingListListContents,
        localIsNewer: Bool
    ) -> ShoppingListListContents {
        if local == server { return local }
        return ShoppingListListContents(
            id: local.id,
            isCompleted: mergeFlag(base?.isCompleted, local.isCompleted, server.isCompleted),
            isImportant: mergeFlag(base?.isImportant, local.isImportant, server.isImportant),
            isHeading: pick(base?.isHeading.eff, local.isHeading.eff, server.isHeading.eff, localIsNewer: localIsNewer),
            text: pick(base?.text, local.text, server.text, localIsNewer: localIsNewer)
        )
    }

    /// Boolean flags normalize nil==false (the DTO defaults). With a base, changed-side-wins; both
    /// changed toward different values is impossible for booleans, so the no-base disagreement case
    /// resolves by OR — "someone checked it off / flagged it" always survives the merge.
    private static func mergeFlag(_ baseValue: Bool?, _ localValue: Bool?, _ serverValue: Bool?) -> Bool {
        let b = baseValue.eff
        let l = localValue.eff
        let s = serverValue.eff
        if l == s { return l }
        if baseValue == nil { return l || s }
        if l != b && s == b { return l }
        if s != b && l == b { return s }
        return l || s
    }

    /// Missing wire dates sort as "older than anything", rounded to the wire's millisecond
    /// resolution before comparing — the Swift equivalent of KMP's `LocalStore.parseOrPast`.
    private static func dateOrPast(_ date: Date?) -> Date {
        (date ?? .distantPast).roundedToWireMillis
    }
}

private extension Optional where Wrapped == Bool {
    /// The effective value of a nullable flag (nil == false, matching the DTO defaults).
    public var eff: Bool { self == true }
}
