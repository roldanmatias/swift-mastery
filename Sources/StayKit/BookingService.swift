// StayKit — the booking engine core.

import Foundation
import Language
import Ownership

/// Why `~Copyable`: the service owns mutable state (catalog, calendars,
/// subscribers). As a Copyable struct, `var other = service` would silently fork
/// that state into two diverging engines. Noncopyable makes "one engine
/// instance" a compile-time fact; pass it `inout` or `borrowing`.
struct BookingService: ~Copyable {
    /// C4 — stored as `any`: the concrete repository is chosen at runtime
    /// (in-memory in tests, a database adapter in production).
    private var listings: any E11.Repository<Listing>
    /// C2 — CoW calendars: `calendars[id]?.block(...)` mutates in place.
    private var calendars: [ListingID: AvailabilityCalendar]
    private var sinks: Set<BookingEventSink> = []
    private let engine: QuoteEngine

    init(
        listings: [Listing],
        calendars: [ListingID: AvailabilityCalendar] = [:],
        engine: QuoteEngine = QuoteEngine()
    ) {
        self.listings = Self.makeRepository(listings)
        var all = calendars
        for listing in listings where all[listing.id] == nil {
            all[listing.id] = AvailabilityCalendar(price: listing.nightlyPrice)
        }
        self.calendars = all
        self.engine = engine
    }

    /// C4 — the factory returns `some`: callers get static types, and we can
    /// swap the implementation without changing the API.
    static func makeRepository(_ listings: [Listing]) -> some E11.Repository<Listing> {
        E11.SortedRepository(listings)
    }

    // MARK: Events (C12)

    mutating func subscribe(_ sink: BookingEventSink) {
        sinks.insert(sink)   // Hashable by identity: subscribing twice is a no-op
    }

    var subscriberCount: Int { sinks.count }

    private func emit(_ event: BookingEvent) {
        for sink in sinks { sink.send(event) }
    }

    // MARK: Search (C5)

    struct SearchResult {
        let listings: [Listing]
        /// How many listings the filter looked at (shows lazy early exit).
        let inspected: Int
    }

    /// Result-builder query, key-path sort rules. Without sort rules, the
    /// filter runs lazily and stops at `limit` (early exit).
    func search(
        sortedBy rules: [E09.SortRule<Listing>] = [],
        limit: Int = 20,
        @E22.SearchQueryBuilder _ query: () -> E22.SearchQuery
    ) -> SearchResult {
        let query = query()
        guard query.isValid else { return SearchResult(listings: [], inspected: 0) }
        // `listings.all()` is `any Collection<Listing>`, and
        //   listings.all().lazy
        // doesn't compile: "member 'lazy' cannot be used on value of type
        // 'any Collection<Listing>'" (its result type depends on `Self`).
        // Passing it to a generic function opens the existential (SE-0352).
        return Self.search(listings.all(), query, rules, limit)
    }

    private static func search(
        _ all: some Collection<Listing>,
        _ query: E22.SearchQuery,
        _ rules: [E09.SortRule<Listing>],
        _ limit: Int
    ) -> SearchResult {
        var inspected = 0
        let matching = all.lazy.filter { listing in
            inspected += 1
            return matches(listing, query)
        }
        guard rules.isEmpty else {
            return SearchResult(listings: Array(matching.sorted(by: rules).prefix(limit)), inspected: inspected)
        }
        // NOT `Array(matching.prefix(limit))`: `matching` is a LazyFilterCollection,
        // and Collection.prefix + Array.init walk it through startIndex /
        // index(after:) / count, re-running the predicate each time (the test
        // measured 6 predicate calls to return 1 listing). One iterator pass
        // evaluates each element exactly once and stops at `limit`.
        var result: [Listing] = []
        for listing in matching {
            result.append(listing)
            if result.count == limit { break }
        }
        return SearchResult(listings: result, inspected: inspected)
    }

    static func matches(_ listing: Listing, _ query: E22.SearchQuery) -> Bool {
        query.components.allSatisfy { component in
            switch component {
            case .destination(let city): listing.city.localizedCaseInsensitiveCompare(city) == .orderedSame
            case .guests(let count): count <= listing.maxGuests
            case .petsAllowed: listing.petsAllowed
            case .amenity(let name): listing.amenities.contains(name)
            case .keyword(let word): listing.title.localizedCaseInsensitiveContains(word)
            case .dates, .glassPreview: true
            }
        }
    }

    // MARK: Quote (C6, C7)

    func quote(
        _ id: ListingID,
        nights: Range<Int>,
        guests request: E21.GuestRequest
    ) throws(ListingError) -> Quote {
        guard let listing = listings.find(id), let calendar = calendars[id] else { throw .notFound(id) }
        guard listing.nightlyPrice > 0 else { throw .invalidPrice(listing.nightlyPrice) }
        guard !nights.isEmpty, calendar.isAvailable(nights) else { throw .unavailable(Self.dates(nights)) }
        // `request.guests` is already clamped to 1...16 by `@Clamped`.
        return engine.quote(for: listing, calendar: calendar, nights: nights, guests: request.guests)
    }

    static func dates(_ nights: Range<Int>) -> Range<Date> {
        let start = Date(timeIntervalSince1970: TimeInterval(nights.lowerBound) * 86_400)
        let end = Date(timeIntervalSince1970: TimeInterval(nights.upperBound) * 86_400)
        return start..<end
    }

    // MARK: Hold → confirm → cancel (C8, C9, C10)

    mutating func hold(_ quote: Quote) throws(BookingError) -> DraftReservation {
        guard let listing = listings.find(quote.listingID) else { throw .listing(.notFound(quote.listingID)) }

        // C8 — one statically-typed call validates three different field types.
        let validator = E16.FormValidator(
            E16.Rule<Range<Int>>(name: "nights") { (1...28).contains($0.count) },
            E16.Rule<Int>(name: "guests") { $0 <= listing.maxGuests },
            E16.Rule<Decimal>(name: "total") { $0 > 0 }
        )
        let failures = validator.failures(quote.nights, quote.guests, quote.total)
        guard failures.isEmpty else { throw .invalidRequest(failures) }

        do {
            let lock = try ReservationLock(acquiring: quote.listingID.lockKey)
            emit(.held(quote.listingID))
            return DraftReservation(quote: quote, lock: lock)
        } catch {
            throw .lockUnavailable(quote.listingID)
        }
    }

    /// Consumes the draft AND the token. On failure the draft is dropped, so
    /// its lock is released by `deinit`; the caller still has the (Copyable)
    /// `Quote` and can `hold` again.
    mutating func confirm(
        _ draft: consuming DraftReservation,
        paying token: consuming PaymentToken
    ) throws(BookingError) -> ConfirmedReservation {
        let listingID = draft.listingID
        let tokenValue = token.redeem()   // single use: `token` is gone now

        // C9 — typed throws end to end; `withRetry` preserves `PaymentError`.
        do {
            try E18.withRetry(attempts: 2) { () throws(PaymentError) in
                try Self.charge(tokenValue, draft.quote.total)
            }
        } catch {
            emit(.paymentFailed(listingID, error))
            throw .payment(error)
        }

        calendars[listingID]?.block(draft.quote.nights)   // in-place CoW mutation
        let id = ReservationID(UUID())
        var receipt = Receipt(reservationID: id, listingID: listingID, total: draft.quote.total)
        receipt.note("confirmed with token •••\(tokenValue.suffix(2))")
        emit(.confirmed(listingID, id))
        return ConfirmedReservation(id: id, receipt: receipt, quote: draft.quote, lock: draft.lock)
    }

    mutating func cancel(_ reservation: consuming ConfirmedReservation, reason: String) -> CancelledReservation {
        // Read the Copyable fields FIRST: `reservation.lock.release()` partially
        // consumes `reservation`, and any later use is
        // "error: 'reservation' used after consume".
        let (id, listingID, nights) = (reservation.id, reservation.listingID, reservation.nights)
        let receipt = reservation.lock.release()
        calendars[listingID]?.unblock(nights)
        emit(.cancelled(listingID, id))
        return CancelledReservation(id: id, listingID: listingID, reason: reason, lockReleasedNormally: !receipt.wasForced)
    }

    func isAvailable(_ id: ListingID, _ nights: Range<Int>) -> Bool {
        calendars[id]?.isAvailable(nights) ?? false
    }

    static func charge(_ token: String, _ amount: Decimal) throws(PaymentError) {
        switch token {
        case "tok_declined": throw .declined
        case "tok_fraud": throw .fraudSuspected
        default: return
        }
    }

    // MARK: Group holds (Swift 6.4, macOS 27)

    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, *)
    mutating func holdGroup(_ quotes: [Quote]) throws(BookingError) -> GroupHold {
        var pool = LockPool()
        for quote in quotes {
            do {
                try pool.acquire(quote.listingID.lockKey)
            } catch {
                throw .lockUnavailable(quote.listingID)   // `pool` dropped → releases what it holds
            }
        }
        for quote in quotes { emit(.held(quote.listingID)) }
        return GroupHold(quotes: quotes, pool: pool)
    }
    #endif
}
