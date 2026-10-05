//
//  RecipeLastPreparedWriterTests.swift
//  SaltyTests
//
//  The one writer for "last made on": it moves the prepared pair and nothing else -- above all not
//  `lastModifiedDate`, which would shove the recipe to the top of the Date Modified sort every time
//  it is cooked -- clears with nil, and stores a picked day at local noon so a time-zone shift can't
//  roll the shown day over.
//

import Testing
import Foundation
import GRDB
import SaltyCore

struct RecipeLastPreparedWriterTests {
    private let t1 = SyncTestClock.t1
    private let t2 = SyncTestClock.t2
    private let t3 = SyncTestClock.t3

    private func library(with recipes: [Recipe]) throws -> DatabaseQueue {
        let queue = try makeSyncTestLibrary()
        try queue.write { db in
            for recipe in recipes {
                try RecipeWriter.save(recipe, in: db, now: recipe.lastModifiedDate)
            }
        }
        return queue
    }

    @Test func settingTheDateMovesOnlyThePreparedPair() throws {
        let queue = try library(with: [Recipe(id: "r1", name: "Loaf", lastModifiedDate: t1)])
        let before = try #require(try recipeRow("r1", in: queue))
        let modifiedBefore: String = before["lastModifiedDate"]

        try queue.write { db in
            try RecipeLastPreparedWriter.setLastMade(SyncTestClock.t0, forRecipeIds: ["r1"], in: db, now: t2)
        }

        let after = try #require(try recipeRow("r1", in: queue))
        #expect(after["lastPrepared"] == SyncTestClock.t0)
        #expect(after["lastModifiedPreparedDate"] == t2)
        let modifiedAfter: String = after["lastModifiedDate"]
        #expect(modifiedAfter == modifiedBefore, "byte-identical: not even re-rounded")
        #expect(after["name"] == "Loaf")
    }

    @Test func nilClearsTheDateButStillStampsTheChange() throws {
        let queue = try library(with: [Recipe(id: "r1", name: "Loaf", lastModifiedDate: t1, lastPrepared: t1, lastModifiedPreparedDate: t2)])

        try queue.write { db in
            try RecipeLastPreparedWriter.setLastMade(nil, forRecipeIds: ["r1"], in: db, now: t3)
        }

        let row = try #require(try recipeRow("r1", in: queue))
        #expect(row["lastPrepared"] == nil as Date?)
        #expect(row["lastModifiedPreparedDate"] == t3, "a clear is an edit sync has to carry")
    }

    @Test func severalRecipesAreStampedTogetherAndNoneIsANoOp() throws {
        let queue = try library(with: [
            Recipe(id: "r1", name: "Loaf", lastModifiedDate: t1),
            Recipe(id: "r2", name: "Rolls", lastModifiedDate: t1),
            Recipe(id: "r3", name: "Buns", lastModifiedDate: t1),
        ])

        try queue.write { db in
            try RecipeLastPreparedWriter.setLastMade(t2, forRecipeIds: ["r1", "r3"], in: db, now: t3)
            try RecipeLastPreparedWriter.setLastMade(t2, forRecipeIds: [], in: db, now: t3)
        }

        #expect(try #require(try recipeRow("r1", in: queue))["lastModifiedPreparedDate"] == t3)
        #expect(try #require(try recipeRow("r2", in: queue))["lastModifiedPreparedDate"] == nil as Date?)
        #expect(try #require(try recipeRow("r3", in: queue))["lastModifiedPreparedDate"] == t3)
    }

    @Test func theStampIsRoundedToWireMillis() throws {
        let queue = try library(with: [Recipe(id: "r1", name: "Loaf", lastModifiedDate: t1)])
        let fine = t2.addingTimeInterval(0.000_4)

        try queue.write { db in
            try RecipeLastPreparedWriter.setLastMade(t1, forRecipeIds: ["r1"], in: db, now: fine)
        }

        #expect(try #require(try recipeRow("r1", in: queue))["lastModifiedPreparedDate"] == t2)
    }

    /// The two US daylight-saving transition days of 2026 and an ordinary day: whatever the current
    /// time zone, the stored instant is 12:00 on the same calendar day the user picked.
    @Test(arguments: ["2026-03-08", "2026-11-01", "2026-06-15"])
    func localNoonStaysOnThePickedDay(day: String) throws {
        let calendar = Calendar.current
        let picked = try #require(calendar.date(from: DateComponents(year: Int(day.prefix(4)),
                                                                   month: Int(day.dropFirst(5).prefix(2)),
                                                                   day: Int(day.suffix(2)), hour: 3)))

        let noon = RecipeLastPreparedWriter.localNoon(on: picked)

        #expect(calendar.component(.hour, from: noon) == 12)
        #expect(calendar.component(.minute, from: noon) == 0)
        #expect(calendar.isDate(noon, inSameDayAs: picked))
    }
}
