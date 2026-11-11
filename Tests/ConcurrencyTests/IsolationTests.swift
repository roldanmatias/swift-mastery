// Tests for C01–C04 (isolation).

import Testing
@testable import Concurrency

@Suite("C01 Isolation domains")
struct C01Tests {
    @Test func actorMethodsRunOnTheActor() async {
        #expect(await PriceCalendar().whereAmI() == "PriceCalendar")
    }

    @Test func synchronousHelperRunsWhereItsCallerRuns() async {
        #expect(await PriceCalendar().whereDoesSyncHelperRun() == "PriceCalendar")
    }

    @MainActor @Test func mainActorCode() {
        #expect(isolationLabel() == "MainActor")
        #expect(mainActorLabel() == "MainActor")
        #expect(syncHelper() == "MainActor")
    }

    @Test func nonisolatedTestHasNoActor() async {
        #expect(isolationLabel() == "nonisolated")
    }

    @Test func everyActorInstanceIsItsOwnDomain() async {
        let source = PriceCalendar(prices: [1: 100, 2: 200])
        let target = PriceCalendar()
        await target.copyPrices(from: source, days: 1...3)

        #expect(await target.price(day: 2) == 200)
        #expect(await target.price(day: 3) == nil)
        #expect(await target.isSameDomain(as: source) == false)
        #expect(await target.isSameDomain(as: target))
    }
}

@Suite("C02 Global actors")
struct C02Tests {
    @Test func typesOnTheSameGlobalActorCallEachOtherSynchronously() async {
        let journal = await SyncJournal()
        let session = await SyncSession(journal: journal)

        #expect(await session.run(listingIDs: [1, 2, 3]) == 3)
        #expect(await journal.entries == ["synced 1", "synced 2", "synced 3"])
        #expect(await syncDomainLabel() == "SyncActor")
    }

    @Test func globalActorIsolatedClassesAreSendable() async {
        let journal = await SyncJournal()
        await Task.detached { await journal.append("from a detached task") }.value
        #expect(await journal.entries.count == 1)
    }

    @Test func assumeIsolatedOnAKnownMainQueueCallback() async {
        let model = await BadgeModel()
        let notifier = LegacyMainQueueNotifier()
        await withCheckedContinuation { continuation in
            model.subscribe(to: notifier) { continuation.resume() }
        }
        #expect(await model.unread == 1)
    }
}

@Suite("C03 Reentrancy")
struct C03Tests {
    private static func availability(_ id: Int) -> Availability {
        Availability(listingID: id, freeNights: [1, 2, 3])
    }

    @Test func naiveCacheFetchesOncePerConcurrentCaller() async throws {
        let fetches = Counter()
        let barrier = AsyncBarrier(count: 5)
        let cache = AvailabilityCache { id in
            fetches.increment()
            await barrier.arrive()          // completes only once all 5 callers are fetching
            return Self.availability(id)
        }

        try await withThrowingTaskGroup(of: Availability.self) { group in
            for _ in 0..<5 { group.addTask { try await cache.availabilityNaive(for: 7) } }
            try await group.waitForAll()
        }
        #expect(fetches.current == 5)       // the bug: 5 network calls for 1 listing
    }

    @Test func dedupedCacheFetchesOnce() async throws {
        let fetches = Counter()
        let gate = AsyncGate()
        let cache = AvailabilityCache { id in
            fetches.increment()
            await gate.wait()
            return Self.availability(id)
        }

        let results = Task {
            try await withThrowingTaskGroup(of: Availability.self) { group in
                for _ in 0..<5 { group.addTask { try await cache.availability(for: 7) } }
                return try await group.reduce(into: []) { $0.append($1) }
            }
        }
        // Wait until the 4 other callers have joined the in-flight fetch, then let it finish.
        #expect(await eventually { await cache.joinedInFlight == 4 })
        await gate.open()

        let values = try await results.value
        #expect(fetches.current == 1)
        #expect(values.count == 5 && Set(values.map(\.listingID)) == [7])
    }

    @Test func aFailedFetchIsNotCached() async throws {
        struct Offline: Error {}
        let fetches = Counter()
        let cache = AvailabilityCache { id in
            if fetches.increment() == 1 { throw Offline() }
            return Self.availability(id)
        }
        await #expect(throws: Offline.self) { try await cache.availability(for: 1) }
        #expect(try await cache.availability(for: 1).listingID == 1)
        #expect(fetches.current == 2)
    }

    @Test func naiveDeskDoubleBooks() async throws {
        let barrier = AsyncBarrier(count: 2)
        let desk = ReservationDesk { _ in await barrier.arrive() }   // both guests reach payment

        async let alice = desk.bookNaive(1...3, guest: "alice")
        async let bob = desk.bookNaive(1...3, guest: "bob")
        _ = try await (alice, bob)

        #expect(await desk.bookings.count == 2)   // the bug: the same nights sold twice
    }

    @Test(arguments: 0..<20)
    func holdBeforeAwaitPreventsDoubleBooking(run: Int) async {
        let desk = ReservationDesk { _ in await Task.yield() }
        let outcomes = await withTaskGroup(of: Result<Booking, BookingError>.self) { group in
            for guest in ["alice", "bob", "carol"] {
                group.addTask {
                    do throws(BookingError) { return .success(try await desk.book(1...3, guest: guest)) }
                    catch { return .failure(error) }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(outcomes.count(where: { (try? $0.get()) != nil }) == 1)
        #expect(outcomes.count(where: { if case .failure(.nightsUnavailable) = $0 { true } else { false } }) == 2)
        #expect(await desk.bookings.count == 1)
    }

    @Test func aDeclinedPaymentReleasesTheHold() async throws {
        let desk = ReservationDesk { guest in
            struct Declined: Error {}
            if guest == "bob" { throw Declined() }
        }
        await #expect(throws: BookingError.paymentDeclined) { try await desk.book(1...3, guest: "bob") }
        #expect(try await desk.book(1...3, guest: "alice").guest == "alice")
    }
}

@Suite("C04 nonisolated and isolated parameters")
struct C04Tests {
    @Test func nonisolatedMembersAreSynchronous() {
        let inbox = HostInbox(hostID: 1)
        #expect(inbox.hostID == 1)                         // no await
        #expect(inbox.description == "HostInbox(1)")
        #expect(Set([inbox, HostInbox(hostID: 1), HostInbox(hostID: 2)]).count == 2)
    }

    @Test func isolatedParameterRunsSeveralOperationsInOneHop() async {
        let inbox = HostInbox(hostID: 1)
        for i in 0..<5 { await inbox.receive(InboxMessage(from: "guest", text: "\(i)")) }

        #expect(await triage(inbox, keepingLast: 2) == 2)
        #expect(await inbox.unreadCount == 0)
    }

    @Test func transactionsDoNotInterleave() async {
        let inbox = HostInbox(hostID: 1)
        let deltas = await withTaskGroup(of: Int.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await inbox.transaction { inbox in
                        let before = inbox.count
                        inbox.receive(InboxMessage(from: "guest", text: "\(i)"))
                        return inbox.count - before
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(deltas.allSatisfy { $0 == 1 })
        #expect(await inbox.count == 100)
    }
}
