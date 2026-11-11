// Tests for C05–C08 (data-race safety).

import Testing
@testable import Concurrency

@Suite("C05 Sendable and Mutex")
struct C05Tests {
    @Test func mutexProtectsStateUnderContention() async {
        let limiter = RateLimiter(capacity: 10)
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<200 { group.addTask { limiter.tryAcquire() } }
            await group.waitForAll()
        }
        #expect(limiter.stats.granted == 10)
        #expect(limiter.stats.rejected == 190)
    }

    @Test func uncheckedSendableWithALock() async {
        let metrics = LegacyMetrics()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1_000 { group.addTask { metrics.record("search") } }
        }
        #expect(metrics.count(of: "search") == 1_000)
    }

    @Test func immutableClassesAndSendableClosuresCrossTasks() async {
        let rates = ExchangeRates(base: "USD", rates: ["EUR": 0.5])
        let format = makeQuoteFormatter(currency: "EUR", rates: rates)
        let quote = Quote(listingID: 1, nights: 3, totalCents: 30_000)
        let text = await Task.detached { format(quote) }.value
        #expect(text == "3 nights · 15000 EUR")
    }
}

@Suite("C06 Regions and sending")
struct C06Tests {
    @Test func aFreshValueCanBeSentToAnActor() async {
        let outbox = ReservationOutbox()
        let draft = ReservationDraft(listingID: 1, nights: 1...2)   // disconnected
        await outbox.submit(draft)                                   // region transferred
        #expect(await outbox.count == 1)
    }

    @Test func sendingParametersAndResults() async {
        let outbox = ReservationOutbox()
        await forward(makeDraft(listingID: 2, nights: 3...4, note: "late check-in"), to: outbox)
        #expect(await outbox.listingIDs == [2])
    }

    @Test func actorsHandOutCopiesNotTheirState() async throws {
        let outbox = ReservationOutbox()
        await outbox.submit(makeDraft(listingID: 3, nights: 1...1, note: "x"))
        let copy = try #require(await outbox.exportFirst())
        copy.listingID = 999                                         // ours to mutate
        #expect(await outbox.listingIDs == [3])
        #expect(copy.notes == ["x"])
    }

    @Test func aTaskOwnsWhatItCaptures() async {
        let task = annotateInBackground(makeDraft(listingID: 4, nights: 1...1, note: "a"), note: "b")
        #expect(await task.value == 2)
    }
}

@Suite("C07 Isolated conformances")
@MainActor
struct C07Tests {
    @Test func isolatedConformanceWorksOnTheMainActor() {
        let cards = [ListingCardModel(nightlyCents: 12_000), ListingCardModel(nightlyCents: 9_900, currency: "EUR")]
        #expect(renderPrices(cards) == ["120 USD/night", "99 EUR/night"])
        #expect(firstPrice(cards) == "120 USD/night")
        #expect(cards[0] == ListingCardModel(nightlyCents: 12_000))
    }
}

@Suite("C08 Isolation-inheriting helpers")
struct C08Tests {
    /// Non-Sendable on purpose: it can only be mutated from the caller's isolation.
    final class Attempts { var count = 0 }
    struct Flaky: Error {}

    @MainActor @Test func isolatedParameterAcceptsNonSendableClosures() async throws {
        let attempts = Attempts()
        let value = try await withRetry(attempts: 5) {
            attempts.count += 1
            if attempts.count < 3 { throw Flaky() }
            return attempts.count
        }
        #expect(value == 3)
    }

    @MainActor @Test func nonsendingAcceptsNonSendableClosures() async throws {
        let attempts = Attempts()
        let value = try await withRetryNonsending(attempts: 5) {
            attempts.count += 1
            if attempts.count < 2 { throw Flaky() }
            return "ok after \(attempts.count)"
        }
        #expect(value == "ok after 2")
    }

    @Test func retryGivesUp() async {
        await #expect(throws: RetryError.exhausted(attempts: 3)) {
            try await withRetry(attempts: 3) { () async throws -> Int in throw Flaky() }
        }
    }

    @MainActor @Test func nonsendingRunsOnTheCallerPlainAsyncHopsOff() async {
        #expect(await nonsendingLabel() == "MainActor")
        #expect(await plainNonisolatedLabel() == "nonisolated")
        #expect(await PriceCalendar().whereAmI() == "PriceCalendar")
    }

    @Test func isolatedAnyClosuresCarryTheirIsolation() async {
        let queue = JobQueue()
        #expect(queue.isolationName(of: { @MainActor in }) == "MainActor")
        #expect(queue.isolationName(of: { @SyncActor in }) == "SyncActor")
        #expect(queue.isolationName(of: {}) == "nonisolated")

        let ran = Flag()
        await queue.run { @MainActor in
            MainActor.assertIsolated()
            ran.set()
        }
        #expect(ran.isSet)
    }
}
