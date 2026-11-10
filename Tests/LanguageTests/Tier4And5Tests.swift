// Tests for Ex 17–23 (errors, data, advanced language).

import Foundation
import Testing
@testable import Language
@testable import Migration

@Suite("Ex17 Result")
struct E17Tests {
    let listing = Listing(title: "Loft", nightlyPrice: 100)

    @Test func zip() throws {
        let a: Result<Int, ListingError> = .success(1)
        let b: Result<String, ListingError> = .success("x")
        #expect(try a.zip(b).get() == (1, "x"))
        let failed: Result<String, ListingError> = .failure(.invalidPrice(0))
        #expect(throws: ListingError.invalidPrice(0)) { try a.zip(failed).get() }
    }

    @Test func collectFailsFast() {
        var calls = 0
        let thunks: [() -> Result<Int, ListingError>] = [
            { calls += 1; return .success(1) },
            { calls += 1; return .failure(.invalidPrice(0)) },
            { calls += 1; return .success(3) },
        ]
        #expect(Result.collect(thunks) == .failure(.invalidPrice(0)))
        #expect(calls == 2)
        #expect(Result<Int, ListingError>.collect([.success(1), .success(2)]) == .success([1, 2]))
    }

    @Test func recoverProducesNever() {
        let failed: Result<Int, ListingError> = .failure(.invalidPrice(0))
        let value = failed.recover { _ in 0 }.get()   // no `try`: Failure == Never
        #expect(value == 0)
    }

    @Test func asyncBridgeKeepsTheErrorType() async {
        let api = E17.LegacyListingAPI([listing])
        do throws(ListingError) {
            let fetched = try await api.fetchListing(id: listing.id)
            #expect(fetched == listing)
            _ = try await api.fetchListing(id: ListingID(UUID()))
            Issue.record("expected notFound")
        } catch {
            switch error {   // exhaustive over ListingError, no default
            case .notFound: break
            case .invalidPrice, .unavailable: Issue.record("wrong error \(error)")
            }
        }
    }

    @Test func resultCatchingKeepsTheErrorType() {
        #expect(E17.validated(Listing(title: "Free", nightlyPrice: 0)) == .failure(.invalidPrice(0)))
        #expect(E17.validated(listing) == .success(listing))
    }
}

@Suite("Ex18 Typed throws")
struct E18Tests {
    let valid = Listing(title: "Loft", nightlyPrice: 100)

    @Test func exhaustiveCatch() {
        #expect(E18.describeValidation(valid) == "valid")
        #expect(E18.describeValidation(Listing(title: "x", nightlyPrice: 0)) == "invalid price 0")
        #expect(E18.describeValidation(Listing(title: "x", nightlyPrice: 10, maxGuests: 0)) == "unavailable")
    }

    @Test func bookComposesErrorDomains() throws {
        let confirmation = try E18.book(valid, nights: 3, paying: .init("ok"))
        #expect(confirmation.amount == 300)
        #expect(throws: BookingError.payment(.declined)) { try E18.book(valid, nights: 1, paying: .init("declined")) }
        #expect(throws: BookingError.payment(.fraudSuspected)) { try E18.book(valid, nights: 1, paying: .init("fraud")) }
        #expect(throws: BookingError.listing(.invalidPrice(-1))) {
            try E18.book(Listing(title: "x", nightlyPrice: -1), nights: 1, paying: .init("ok"))
        }
    }

    @Test func retrySucceedsWithinBudget() throws {
        var calls = 0
        let value = try E18.withRetry(attempts: 3) { () throws(ListingError) -> Int in
            calls += 1
            if calls < 3 { throw .invalidPrice(0) }
            return 42
        }
        #expect(value == 42)
        #expect(calls == 3)
    }

    @Test func retryRethrowsTheSameType() {
        var calls = 0
        #expect(throws: ListingError.self) {
            try E18.withRetry(attempts: 2) { () throws(ListingError) -> Int in
                calls += 1
                throw .invalidPrice(0)
            }
        }
        #expect(calls == 2)
    }

    @Test func nonThrowingClosureNeedsNoTry() {
        let value = E18.withRetry(attempts: 3) { 42 }   // E == Never
        #expect(value == 42)
    }

    @Test func typedMap() throws {
        let prices = try E18.mapAll([1, 2]) { (n: Int) throws(ListingError) -> Decimal in Decimal(n * 10) }
        #expect(prices == [10, 20])
        let doubled = E18.mapAll([1, 2]) { $0 * 2 }      // no `try`
        #expect(doubled == [2, 4])
    }
}

@Suite("Ex19 Advanced Codable")
struct E19Tests {
    static let json = """
    {
      "listing_id": "5F1B6C1E-0000-0000-0000-000000000001",
      "title": "Loft in Palermo",
      "location": { "lat": -34.58, "lng": -58.42 },
      "price": { "amount": "120.50", "currency": "USD" },
      "available_from": "2026-12-01",
      "updated_at": "2026-11-06T10:15:00Z",
      "blocks": [
        { "type": "text", "body": "Sunny loft" },
        { "type": "photo", "url": "https://example.com/p.jpg", "caption": null },
        { "type": "amenities", "items": ["wifi", "ac"] },
        { "type": "video_tour", "url": "https://example.com/v.mp4" }
      ]
    }
    """

    func decode(_ text: String, userInfo: [CodingUserInfoKey: any Sendable] = [:]) throws -> E19.ImportedListing {
        let decoder = JSONDecoder()
        decoder.userInfo = userInfo
        return try decoder.decode(E19.ImportedListing.self, from: Data(text.utf8))
    }

    @Test func goldenDecode() throws {
        let listing = try decode(Self.json)
        #expect(listing.title == "Loft in Palermo")
        #expect(listing.latitude == -34.58)
        #expect(listing.longitude == -58.42)
        #expect(listing.price == Decimal(string: "120.50"))
        #expect(listing.availableFrom == Date(timeIntervalSince1970: 1_796_083_200))   // 2026-12-01 UTC
        #expect(listing.updatedAt == Date(timeIntervalSince1970: 1_793_960_100))       // 2026-11-06T10:15:00Z
        #expect(listing.blocks == [
            .text(body: "Sunny loft"),
            .photo(url: URL(string: "https://example.com/p.jpg")!, caption: nil),
            .amenities(["wifi", "ac"]),
            .unknown(type: "video_tour"),
        ])
    }

    @Test func roundTrip() throws {
        let original = try decode(Self.json)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(E19.ImportedListing.self, from: data)
        #expect(decoded == original)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["location"] is [String: Any])
        #expect((object["price"] as? [String: Any])?["amount"] is String)
    }

    @Test func malformedPricePointsAtThePath() throws {
        let broken = Self.json.replacingOccurrences(of: "\"120.50\"", with: "\"12,5x\"")
        do {
            _ = try decode(broken)
            Issue.record("expected a DecodingError")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.codingPath.map(\.stringValue) == ["price", "amount"])
        }
    }

    @Test func userInfoProvidesDefaultCurrency() throws {
        let noCurrency = Self.json.replacingOccurrences(of: ", \"currency\": \"USD\"", with: "")
        let listing = try decode(noCurrency, userInfo: [E19.defaultCurrencyKey: "ARS"])
        #expect(listing.currency == "ARS")
    }
}

@Suite("Ex20 @diagnose (behavior; diagnostics are verified by the build)")
struct E20Tests {
    @Test func legacyAdapterStillWorks() async {
        let listing = Listing(title: "Loft", nightlyPrice: 100)
        let adapter = LegacyListingAdapter(api: E17.LegacyListingAPI([listing]))
        let result = await withCheckedContinuation { continuation in
            adapter.fetch(listing.id) { continuation.resume(returning: $0) }
        }
        #expect(result == .success(listing))
    }
}

@Suite("Ex21 Property wrappers")
struct E21Tests {
    @Test func clampsOnInitAndSet() {
        var request = E21.GuestRequest(guests: 20, note: "  bring towels \n")
        #expect(request.guests == 16)
        #expect(request.guestsReport == .init(wasClamped: true, lastRawValue: 20))
        #expect(request.note == "bring towels")

        request.guests = 5
        #expect(request.guests == 5)
        #expect(request.guestsReport.wasClamped == false)

        request.guests = 0
        #expect(request.guests == 1)
    }

    @Test func compositionOrderMatters() {
        var forms = E21.TitleForms("   ")
        #expect(forms.trimmedOutside == "")           // NonEmpty ran first, then Trimmed
        #expect(forms.nonEmptyOutside == "Untitled")  // Trimmed ran first, then NonEmpty
        forms.trimmedOutside = "  Loft "
        #expect(forms.trimmedOutside == "Loft")
    }

    @Test func parameterWrapper() {
        #expect(E21.rename("  Loft  ") == "Loft")
    }
}

@Suite("Ex22 Result builders")
struct E22Tests {
    let checkIn = Date(timeIntervalSince1970: 0)
    let checkOut = Date(timeIntervalSince1970: 86_400 * 3)

    @Test func everyControlFlowForm() {
        let includePets = true
        let flexible = false
        let amenities = ["wifi", "ac"]
        let query = E22.SearchQuery {
            E22.Destination("Buenos Aires")
            E22.Guests(4)
            if includePets { E22.PetsAllowed() }
            if flexible { E22.DateRange.flexible(weeks: 2) } else { E22.DateRange(checkIn, checkOut) }
            for amenity in amenities { E22.Amenity(amenity) }
            if #available(macOS 26, iOS 27, *) { E22.GlassPreview() }
            "loft"
        }
        #expect(query.components == [
            .destination("Buenos Aires"), .guests(4), .petsAllowed,
            .dates(.exact(checkIn, checkOut)), .amenity("wifi"), .amenity("ac"),
            .glassPreview, .keyword("loft"),
        ])
        #expect(query.isValid)
        #expect(query.destination == "Buenos Aires")
        #expect(query.keywords == ["loft"])
    }

    @Test func optionalAndElseBranches() {
        let query = E22.SearchQuery {
            E22.Destination("Rosario")
            if false { E22.PetsAllowed() }
            if true { E22.DateRange.flexible(weeks: 2) } else { E22.DateRange(checkIn, checkOut) }
        }
        #expect(query.components == [.destination("Rosario"), .dates(.flexible(weeks: 2))])
    }

    @Test func finalResultValidates() {
        #expect(E22.SearchQuery {}.issues == [.missingDestination])
        let twice = E22.SearchQuery {
            E22.Destination("A")
            E22.Destination("B")
            E22.Guests(20)
        }
        #expect(twice.issues == [.multipleDestinations(2), .invalidGuests(20)])
    }
}

@Suite("Ex23 Macros (usage)")
struct E23Tests {
    @Test func compileTimeURL() {
        #expect(E23.homepage.absoluteString == "https://example.com/listings")
    }

    @Test func addAsyncGeneratedPeer() async throws {
        let listing = Listing(title: "Loft", nightlyPrice: 100)
        let catalog = E23.LegacyCatalog([listing])
        let fetched = try await catalog.fetchListing(id: listing.id)   // generated by @AddAsync
        #expect(fetched == listing)
        await #expect(throws: ListingError.notFound(ListingID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!))) {
            try await catalog.fetchListing(id: ListingID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!))
        }
    }
}
