// C03 — Actor reentrancy: every `await` inside an actor is a point where other
// calls can run and change its state. The compiler can't see these bugs.

package struct Availability: Sendable, Equatable {
    package let listingID: Int
    package let freeNights: Set<Int>
    package init(listingID: Int, freeNights: Set<Int>) {
        self.listingID = listingID
        self.freeNights = freeNights
    }
}

// MARK: - Bug 1: duplicate work (check, await, then act)

package actor AvailabilityCache {
    package typealias Fetch = @Sendable (Int) async throws -> Availability

    private let fetch: Fetch
    private var cache: [Int: Availability] = [:]
    private var inFlight: [Int: Task<Availability, any Error>] = [:]
    /// How many callers joined an existing fetch instead of starting one.
    package private(set) var joinedInFlight = 0

    package init(fetch: @escaping Fetch) { self.fetch = fetch }

    /// ❌ Reentrancy bug: N concurrent callers for the same listing all miss the
    /// cache, because the cache is only written *after* the `await`, so they
    /// fetch N times.
    package func availabilityNaive(for listingID: Int) async throws -> Availability {
        if let cached = cache[listingID] { return cached }
        let fresh = try await fetch(listingID)          // suspension point
        cache[listingID] = fresh
        return fresh
    }

    /// ✅ Record the in-flight work *before* suspending, so later callers join it.
    package func availability(for listingID: Int) async throws -> Availability {
        if let cached = cache[listingID] { return cached }
        if let running = inFlight[listingID] {
            joinedInFlight += 1
            return try await running.value
        }

        let task = Task { try await fetch(listingID) }
        inFlight[listingID] = task
        defer { inFlight[listingID] = nil }             // also on failure: the next call retries

        let fresh = try await task.value
        cache[listingID] = fresh
        return fresh
    }
}

// MARK: - Bug 2: double booking (an invariant checked before an await)

package enum BookingError: Error, Equatable, Sendable {
    case nightsUnavailable
    case paymentDeclined
}

package struct Booking: Sendable, Equatable {
    package let guest: String
    package let nights: ClosedRange<Int>
}

package actor ReservationDesk {
    package typealias Authorize = @Sendable (_ guest: String) async throws -> Void

    private let authorize: Authorize
    private var booked: Set<Int> = []
    package private(set) var bookings: [Booking] = []

    package init(authorize: @escaping Authorize) { self.authorize = authorize }

    /// ❌ Checks availability, suspends for payment, then books. Two guests can
    /// both pass the check while the first is suspended.
    package func bookNaive(_ nights: ClosedRange<Int>, guest: String) async throws(BookingError) -> Booking {
        guard booked.isDisjoint(with: nights) else { throw .nightsUnavailable }
        do { try await authorize(guest) } catch { throw .paymentDeclined }
        booked.formUnion(nights)
        let booking = Booking(guest: guest, nights: nights)
        bookings.append(booking)
        return booking
    }

    /// ✅ Mutate state synchronously *before* the await (a hold), and roll it back
    /// on failure. The invariant is never exposed across a suspension point.
    package func book(_ nights: ClosedRange<Int>, guest: String) async throws(BookingError) -> Booking {
        guard booked.isDisjoint(with: nights) else { throw .nightsUnavailable }
        booked.formUnion(nights)                        // hold
        do {
            try await authorize(guest)
        } catch {
            booked.subtract(nights)                     // release the hold
            throw .paymentDeclined
        }
        let booking = Booking(guest: guest, nights: nights)
        bookings.append(booking)
        return booking
    }
}
