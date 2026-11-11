// Tests for C13–C16 (structured concurrency and async sequences).

import Testing
@testable import Concurrency

@Suite("C13 async let and task groups")
struct C13Tests {
    @Test func asyncLetFansOut() async throws {
        let aggregator = QuoteAggregator(services: QuoteServices(
            nightly: { _ in 30_000 }, fees: { _ in 4_500 }, tax: { _ in 2_000 }
        ))
        #expect(try await aggregator.quote(listingID: 1).totalCents == 36_500)
        #expect(try await aggregator.quoteFailFast(listingID: 1).totalCents == 36_500)
    }

    @Test func asyncLetAwaitsInTheOrderWritten() async throws {
        let gate = AsyncGate()
        let nightlyFinished = Flag()
        let aggregator = QuoteAggregator(services: QuoteServices(
            nightly: { _ in await gate.wait(); nightlyFinished.set(); return 1 },
            fees: { _ in throw QuoteError.feesUnavailable },          // fails immediately
            tax: { _ in 1 }
        ))
        let quote = Task { try await aggregator.quote(listingID: 1) }
        await gate.open()
        await #expect(throws: QuoteError.feesUnavailable) { try await quote.value }
        #expect(nightlyFinished.isSet)      // the error only surfaced after `nightly` completed
    }

    @Test func taskGroupFailsFastAndCancelsSiblings() async {
        let nightlyCancelled = Flag()
        let aggregator = QuoteAggregator(services: QuoteServices(
            nightly: { _ in
                await suspendUntilCancelled()
                if Task.isCancelled { nightlyCancelled.set() }
                return 0
            },
            fees: { _ in throw QuoteError.feesUnavailable },
            tax: { _ in 1 }
        ))
        await #expect(throws: QuoteError.feesUnavailable) { try await aggregator.quoteFailFast(listingID: 1) }
        #expect(nightlyCancelled.isSet)     // groups wait for cancelled children before returning
    }

    @Test func hedgedRequestReturnsTheFirstSuccess() async throws {
        let slowCancelled = Flag()
        let value = try await QuoteAggregator.firstResponse(from: [
            { await suspendUntilCancelled(); if Task.isCancelled { slowCancelled.set() }; return 1 },
            { throw QuoteError.feesUnavailable },
            { 7 },
        ])
        #expect(value == 7)
        #expect(slowCancelled.isSet)
    }

    @Test func hedgedRequestFailsWhenEveryMirrorFails() async {
        await #expect(throws: QuoteError.noMirrorResponded) {
            try await QuoteAggregator.firstResponse(from: [{ throw QuoteError.feesUnavailable }])
        }
    }
}

@Suite("C14 Cancellation")
struct C14Tests {
    @Test func importStopsCooperativelyAndKeepsPartialWork() async {
        let (pages, pagesContinuation) = AsyncStream.makeStream(of: [Int].self)
        let (stored, storedContinuation) = AsyncStream.makeStream(of: Int.self)
        let task = Task {
            await ListingImporter.importPages(pages) { page in storedContinuation.yield(page.count) }
        }
        pagesContinuation.yield([1, 2, 3])
        var storedIterator = stored.makeAsyncIterator()
        #expect(await storedIterator.next() == 3)   // first page stored

        task.cancel()
        pagesContinuation.yield([4, 5])
        pagesContinuation.finish()

        #expect(await task.value == ImportReport(imported: 3, wasCancelled: true))
    }

    @Test func cancellationHandlerBridgesTheLegacyCancelToken() async {
        let download = LegacyDownload()
        let task = Task { try await download.bytes() }
        #expect(await eventually { download.hasPendingHandler })

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(download.wasCancelled)
    }

    @Test func cancellationBeforeStartIsNotLost() async {
        let download = LegacyDownload()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }   // cancelled before bytes() registers anything
            return try await download.bytes()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func legacyDownloadCompletes() async throws {
        let download = LegacyDownload()
        let task = Task { try await download.bytes() }
        #expect(await eventually { download.hasPendingHandler })
        download.complete(with: [1, 2, 3])
        #expect(try await task.value == [1, 2, 3])
    }

    @Test func onlyStructuredChildrenInheritCancellation() async {
        let observed = await Task { await Inheritance.observeAfterCancelling() }.value
        #expect(observed == .init(asyncLetCancelled: true, unstructuredCancelled: false, detachedCancelled: false))
    }
}

@Suite("C15 AsyncStream")
struct C15Tests {
    @Test func bridgesDelegateCallbacks() async {
        let client = CalendarSyncClient()
        var changes = client.changes().makeAsyncIterator()
        client.push(AvailabilityChange(listingID: 1, freeNights: 3))
        client.push(AvailabilityChange(listingID: 2, freeNights: 5))

        #expect(await changes.next()?.listingID == 1)
        #expect(await changes.next()?.listingID == 2)
        #expect(client.observerCount == 1)
    }

    @Test func onTerminationUnregistersTheObserver() async {
        let client = CalendarSyncClient()
        let stream = client.changes()
        let consumer = Task { for await _ in stream {} }
        #expect(client.observerCount == 1)

        consumer.cancel()
        await consumer.value
        #expect(client.observerCount == 0)
    }

    @Test func bufferingNewestKeepsOnlyTheLatest() async {
        let client = CalendarSyncClient()
        var latest = client.changes(bufferingPolicy: .bufferingNewest(1)).makeAsyncIterator()
        for nights in 1...3 { client.push(AvailabilityChange(listingID: 1, freeNights: nights)) }
        #expect(await latest.next()?.freeNights == 3)
    }

    @Test func throwingStreamsEndWithTheError() async {
        let changes = (1...2).map { AvailabilityChange(listingID: $0, freeNights: 1) }
        var received: [Int] = []
        await #expect(throws: SyncFailure.connectionLost) {
            for try await change in replay(changes, thenFail: true) { received.append(change.listingID) }
        }
        #expect(received == [1, 2])
    }
}

@Suite("C16 AsyncSequence operators and Observations")
struct C16Tests {
    @Test func removeDuplicatesKeepsTheFailureType() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        for value in [1, 1, 2, 2, 2, 3, 1] { continuation.yield(value) }
        continuation.finish()

        var values: [Int] = []
        for await value in stream.removeDuplicates() { values.append(value) }   // no `try`: Failure == Never
        #expect(values == [1, 2, 3, 1])
    }

    @MainActor @Test func observationsEmitTheInitialValueThenTransactions() async {
        let filters = SearchFilters()
        var changes = filters.maxPriceChanges.makeAsyncIterator()
        #expect(await changes.next() == 50_000)

        filters.maxPriceCents = 1
        filters.maxPriceCents = 2
        filters.maxPriceCents = 30_000      // same synchronous turn → one value
        #expect(await changes.next() == 30_000)
    }
}
