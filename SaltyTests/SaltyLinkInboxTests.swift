//
//  SaltyLinkInboxTests.swift
//  SaltyTests
//
//  The hand-off from an App Intent to a main window: a request is taken exactly once, and a newer
//  request replaces one no window has opened yet.
//

import Testing
@testable import Salty

@MainActor
struct SaltyLinkInboxTests {
    @Test func aRequestIsTakenOnce() {
        let inbox = SaltyLinkInbox()
        inbox.request(.recipe(id: "r1"))

        #expect(inbox.take() == .recipe(id: "r1"))
        #expect(inbox.take() == nil)
        #expect(inbox.pending == nil)
    }

    @Test func aNewerRequestReplacesAnUnopenedOne() {
        let inbox = SaltyLinkInbox()
        inbox.request(.recipe(id: "r1"))
        inbox.request(.recipe(id: "r2"))

        #expect(inbox.take() == .recipe(id: "r2"))
    }

    @Test func nothingWaitingTakesNothing() {
        #expect(SaltyLinkInbox().take() == nil)
    }
}
