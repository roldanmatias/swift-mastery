// Capstone acceptance tests (StayKit).

import Foundation
@testable import Language
@testable import Ownership
import Testing
@testable import StayKit

enum Fixtures {
    static let loft = Listing(title: "Loft in Palermo", city: "Buenos Aires", nightlyPrice: 100, rating: 4.9,
                              maxGuests: 4, amenities: ["wifi", "ac"], petsAllowed: true)
    static let studio = Listing(title: "Studio near Obelisco", city: "Buenos Aires", nightlyPrice: 60, rating: 4.6,
                                maxGuests: 2, amenities: ["wifi"])
    static let house = Listing(title: "House with pool", city: "Buenos Aires", nightlyPrice: 180, rating: 4.9,
                               maxGuests: 8, amenities: ["wifi", "pool"], petsAllowed: true)
    static let rosario = Listing(title: "Riverside loft", city: "Rosario", nightlyPrice: 70, maxGuests: 3)

    /// Every test gets fresh listing IDs (the lock registry is process-wide).
    static func fresh() -> [Listing] {
        [loft, studio, house, rosario].map { template in
            Listing(title: template.title, city: template.city, nightlyPrice: template.nightlyPrice,
                    rating: template.rating, maxGuests: template.maxGuests,
                    amenities: template.amenities, petsAllowed: template.petsAllowed)
        }
    }

    /// Flat engine (no weekday surcharge) so totals are easy to check by hand.
    static let flatEngine = QuoteEngine(weekdayMultipliers: .init(repeating: 1), cleaningFee: 30, weeklyDiscountPercent: 10)
}

private var registry: LockRegistry { .shared }

@Suite("Search")
struct SearchTests {
    @Test func dslFiltersAndSorts() {
        let listings = Fixtures.fresh()
        let service = BookingService(listings: listings)
        let result = service.search(sortedBy: [.init(\.rating, ascending: false), .init(\.nightlyPrice)]) {
            E22.Destination("buenos aires")
            E22.Guests(2)
            E22.Amenity("wifi")
        }
        #expect(result.listings.map(\.title) == ["Loft in Palermo", "House with pool", "Studio near Obelisco"])
    }

    @Test func petsAndKeywords() {
        let service = BookingService(listings: Fixtures.fresh())
        let result = service.search {
            E22.Destination("Buenos Aires")
            E22.PetsAllowed()
            "loft"
        }
        #expect(result.listings.map(\.title) == ["Loft in Palermo"])
    }

    @Test func lazyPrefixStopsEarly() {
        let service = BookingService(listings: Fixtures.fresh())
        let result = service.search(limit: 1) { E22.Destination("Buenos Aires") }
        #expect(result.listings.count == 1)
        #expect(result.inspected == 1)   // stopped at the first match, didn't scan all 4
    }

    @Test func invalidQueryReturnsNothing() {
        let service = BookingService(listings: Fixtures.fresh())
        let empty = service.search { E22.Guests(2) }.listings.isEmpty   // no destination
        #expect(empty)
    }
}

@Suite("Pricing")
struct PricingTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let nights: Range<Int>
        let expected: Decimal
        var testDescription: String { "\(nights.count) nights → \(expected)" }
    }

    // Loft: 100/night, cleaning 30, 10% off from 7 nights.
    static let cases: [Case] = [
        Case(nights: 0..<1, expected: 130),
        Case(nights: 0..<3, expected: 330),
        Case(nights: 10..<16, expected: 630),
        Case(nights: 0..<7, expected: 660),       // 700 × 0.9 + 30
        Case(nights: 30..<44, expected: 1290),    // 1400 × 0.9 + 30
    ]

    @Test(arguments: cases)
    func quoteTotals(_ testCase: Case) throws {
        let loft = Fixtures.fresh()[0]
        let service = BookingService(listings: [loft], engine: Fixtures.flatEngine)
        let quote = try service.quote(loft.id, nights: testCase.nights, guests: .init(guests: 2, note: ""))
        #expect(quote.total == testCase.expected)
        #expect(quote.averageNightly == 100)      // InlineArray table + Span average
    }

    @Test func weekdaySurchargeComesFromTheInlineTable() throws {
        let loft = Fixtures.fresh()[0]
        let service = BookingService(listings: [loft])   // default table: days 4,5,6 are 1.2, 1.25, 1.1
        let quote = try service.quote(loft.id, nights: 0..<7, guests: .init(guests: 2, note: ""))
        #expect(abs(quote.averageNightly - (100 * (4 + 1.2 + 1.25 + 1.1) / 7)) < 1e-9)
    }

    @Test func guestsAreClampedByThePropertyWrapper() throws {
        let loft = Fixtures.fresh()[0]
        let service = BookingService(listings: [loft])
        let quote = try service.quote(loft.id, nights: 0..<2, guests: .init(guests: 40, note: "  team  "))
        #expect(quote.guests == 16)
    }

    @Test func quoteErrorsAreTyped() {
        let loft = Fixtures.fresh()[0]
        let service = BookingService(listings: [loft])
        let missing = ListingID(UUID())
        #expect(throws: ListingError.notFound(missing)) {
            try service.quote(missing, nights: 0..<2, guests: .init(guests: 1, note: ""))
        }
        #expect(throws: ListingError.self) {
            try service.quote(loft.id, nights: 400..<402, guests: .init(guests: 1, note: ""))
        }
    }
}

@Suite("Booking lifecycle")
struct BookingLifecycleTests {
    @Test func happyPath() throws {
        let loft = Fixtures.fresh()[0]
        var service = BookingService(listings: [loft], engine: Fixtures.flatEngine)
        // E15.RecordingSink records E15.BookingEvent; StayKit needs its own sink type:
        final class Events: E15.EventSink { var all: [BookingEvent] = []; func send(_ e: BookingEvent) { all.append(e) } }
        let events = Events()
        service.subscribe(BookingEventSink(events))
        service.subscribe(BookingEventSink(events))      // deduplicated by identity
        let subscribers = service.subscriberCount   // #expect can't capture a noncopyable receiver
        #expect(subscribers == 1)

        let quote = try service.quote(loft.id, nights: 3..<6, guests: .init(guests: 2, note: ""))
        let draft = try service.hold(quote)
        #expect(registry.isHeld(loft.id.lockKey))

        let confirmed = try service.confirm(draft, paying: PaymentToken("tok_visa_42"))
        #expect(confirmed.receipt.total == 330)
        #expect(confirmed.receipt.trail == ["confirmed with token •••42"])
        let blocked = !service.isAvailable(loft.id, 3..<6)
        #expect(blocked)
        #expect(registry.isHeld(loft.id.lockKey))        // the lock moved into the confirmed state

        let cancelled = service.cancel(confirmed, reason: "plans changed")
        #expect(cancelled.lockReleasedNormally)
        #expect(!registry.isHeld(loft.id.lockKey))
        let freed = service.isAvailable(loft.id, 3..<6)
        #expect(freed)

        #expect(events.all.count == 3)
        if case .held = events.all[0], case .confirmed = events.all[1], case .cancelled = events.all[2] {} else {
            Issue.record("unexpected events \(events.all)")
        }
    }

    @Test func declinedPaymentReleasesTheHoldAndAllowsRetry() throws {
        let loft = Fixtures.fresh()[0]
        var service = BookingService(listings: [loft])
        let quote = try service.quote(loft.id, nights: 0..<2, guests: .init(guests: 2, note: ""))

        let draft = try service.hold(quote)
        // Not `#expect(throws:) { … }`: a closure can only BORROW a captured
        // noncopyable value ("'draft' is borrowed and cannot be consumed").
        do throws(BookingError) {
            _ = try service.confirm(draft, paying: PaymentToken("tok_declined"))
            Issue.record("expected a declined payment")
        } catch {
            #expect(error == .payment(.declined))
        }
        // The draft was consumed and dropped → its lock was released by deinit.
        #expect(!registry.isHeld(loft.id.lockKey))
        #expect(registry.receipts(for: loft.id.lockKey).last?.wasForced == true)

        // The Quote is Copyable, so the caller can retry.
        let retry = try service.confirm(try service.hold(quote), paying: PaymentToken("tok_ok"))
        #expect(retry.listingID == loft.id)
    }

    @Test func doubleHoldIsRejected() throws {
        let loft = Fixtures.fresh()[0]
        var service = BookingService(listings: [loft])
        let quote = try service.quote(loft.id, nights: 0..<2, guests: .init(guests: 2, note: ""))
        let first = try service.hold(quote)
        #expect(throws: BookingError.lockUnavailable(loft.id)) { _ = try service.hold(quote) }
        _ = first.listingID
    }

    @Test func droppingADraftReleasesItsLock() throws {
        let loft = Fixtures.fresh()[0]
        var service = BookingService(listings: [loft])
        let quote = try service.quote(loft.id, nights: 0..<2, guests: .init(guests: 2, note: ""))
        do {
            let draft = try service.hold(quote)
            _ = draft.listingID
        }
        #expect(!registry.isHeld(loft.id.lockKey))
    }

    @Test func validatorRejectsBadRequests() throws {
        let studio = Fixtures.fresh()[1]                     // max 2 guests
        var service = BookingService(listings: [studio])
        let quote = try service.quote(studio.id, nights: 0..<30, guests: .init(guests: 5, note: ""))
        #expect(throws: BookingError.invalidRequest(["nights", "guests"])) { _ = try service.hold(quote) }
    }

    // Compile-time guarantees (documented, can't be runtime tests):
    //
    //   let confirmed = try service.confirm(draft, paying: token)
    //   _ = try service.confirm(draft, paying: token)
    //   // error: 'draft' consumed more than once / 'token' consumed more than once
    //
    //   let copy = service; use(service)
    //   // error: 'service' used after consume   (BookingService is ~Copyable: no accidental forks)
}

#if compiler(>=6.4)
@Suite("Swift 6.4 features in StayKit")
struct StayKit64Tests {
    @Test func paymentTokensAreHashableWithoutCopying() {
        // `Ownership` (Ex 26) also declares `PaymentToken`: a module selector disambiguates.
        let a = StayKit::PaymentToken("tok_1"), b = StayKit::PaymentToken("tok_1")
        let equal = a == b
        #expect(equal)
    }

    @Test func memberwiseInitSkipsPrivateDefaults() {
        // SE-0502: no `auditTrail:` parameter, and the init is internal (not private).
        let receipt = Receipt(reservationID: ReservationID(UUID()), listingID: ListingID(UUID()), total: 10)
        #expect(receipt.trail.isEmpty)
    }

    @available(macOS 27, iOS 27, *)
    @Test func groupHoldIsAllOrNothing() throws {
        let listings = Fixtures.fresh()
        var service = BookingService(listings: listings)
        let quotes = try listings.prefix(3).map { try service.quote($0.id, nights: 0..<2, guests: .init(guests: 1, note: "")) }

        let blocker = try service.hold(quotes[2])           // third listing already held
        #expect(throws: BookingError.lockUnavailable(quotes[2].listingID)) { _ = try service.holdGroup(quotes) }
        #expect(!registry.isHeld(quotes[0].listingID.lockKey))   // partial pool was released
        _ = blocker.listingID
    }
}
#endif

@Suite("Import and legacy bridge")
struct ImportTests {
    static let json = """
    [{
      "listing_id": "5F1B6C1E-0000-0000-0000-0000000000AA",
      "title": "Imported loft",
      "location": { "lat": -34.58, "lng": -58.42 },
      "price": { "amount": "95.50", "currency": "USD" },
      "available_from": "2026-12-01",
      "updated_at": "2026-11-06T10:15:00Z",
      "blocks": [{ "type": "amenities", "items": ["wifi"] }, { "type": "video_tour", "url": "https://x" }]
    }]
    """

    @Test func importsLegacyJSON() throws {
        let listings = try ListingImporter.importListings(from: Data(Self.json.utf8), city: "Buenos Aires")
        #expect(listings.count == 1)
        #expect(listings[0].nightlyPrice == Decimal(string: "95.50"))
        #expect(listings[0].amenities == ["wifi"])
    }

    @Test func asyncTwinGeneratedByMacro() async throws {
        let loft = Fixtures.fresh()[0]
        let client = LegacyCatalogClient([loft])
        #expect(try await client.fetchListing(id: loft.id) == loft)
        #expect(LegacyListingBridge(client: client).listing(loft.id) == loft)
    }
}
