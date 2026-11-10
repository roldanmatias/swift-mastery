// Tests for Ex 01–06 (types and semantics).

import Foundation
import Testing
@testable import Language
import Payments
import Pricing

@Suite("Ex01 Value vs reference semantics")
struct E01Tests {
    let photo = URL(string: "https://example.com/1.jpg")!

    @Test func brokenListingSharesGallery() {
        let original = E01.BrokenListing(title: "Loft", nightlyPrice: 100, gallery: .init())
        let copy = original
        copy.gallery.urls.append(photo)          // compiles on a `let`: only the reference is frozen
        #expect(original.gallery.urls == [photo]) // the bug: the original changed
    }

    @Test func copyDoesNotShareGallery() {
        let original = E01.Listing(title: "Loft", nightlyPrice: 100, host: E01.Host(name: "Ana"))
        var copy = original
        copy.gallery.urls.append(photo)
        #expect(original.gallery.urls.isEmpty)
        #expect(copy.gallery.urls == [photo])
    }

    @Test func hostIsShared() {
        let host = E01.Host(name: "Ana")
        let a = E01.Listing(title: "Loft", nightlyPrice: 100, host: host)
        let b = E01.Listing(title: "Studio", nightlyPrice: 80, host: host)
        b.host.name = "Ana María"
        #expect(a.host === b.host)
        #expect(a.host.name == "Ana María")
    }
}

@Suite("Ex02 Pattern matching")
struct E02Tests {
    typealias Rule = E02.PricingRule

    struct Case: Sendable, CustomTestStringConvertible {
        let rule: Rule
        let nights: Int
        let expected: Decimal
        var testDescription: String { "\(rule) × \(nights) = \(expected)" }
    }

    static let cases: [Case] = [
        Case(rule: .nightly(100), nights: 3, expected: 300),
        Case(rule: .cleaningFee(50), nights: 3, expected: 50),
        Case(rule: .combined(.nightly(100), .cleaningFee(50)), nights: 2, expected: 250),
        Case(rule: .percentOff(10, .nightly(100)), nights: 10, expected: 900),
        Case(rule: .ifStayAtLeast(nights: 7, then: .percentOff(20, .nightly(100)), else: .nightly(100)), nights: 7, expected: 560),
        Case(rule: .ifStayAtLeast(nights: 7, then: .percentOff(20, .nightly(100)), else: .nightly(100)), nights: 3, expected: 300),
        Case(rule: .percentOff(50, .percentOff(50, .nightly(100))), nights: 2, expected: 50),
        Case(rule: .combined(.nightly(0), .cleaningFee(30)), nights: 5, expected: 30),
    ]

    static let trees: [Rule] = cases.map(\.rule) + [
        .percentOff(0, .nightly(80)),
        .percentOff(20, .percentOff(50, .nightly(100))),
        .percentOff(10, .percentOff(15, .nightly(100))),
        .ifStayAtLeast(nights: 5, then: .cleaningFee(10), else: .cleaningFee(10)),
        .combined(.cleaningFee(0), .percentOff(0, .nightly(0))),
    ]

    @Test(arguments: cases)
    func total(_ testCase: Case) {
        #expect(testCase.rule.total(nights: testCase.nights) == testCase.expected)
    }

    @Test(arguments: trees)
    func simplifiedIsIdempotent(_ rule: Rule) {
        #expect(rule.simplified().simplified() == rule.simplified())
    }

    @Test(arguments: trees)
    func simplifiedPreservesMeaning(_ rule: Rule) {
        for nights in 1...40 {
            #expect(rule.total(nights: nights) == rule.simplified().total(nights: nights))
        }
    }

    @Test func specificRewrites() {
        #expect(Rule.percentOff(0, .nightly(80)).simplified() == .nightly(80))
        #expect(Rule.percentOff(50, .percentOff(50, .nightly(100))).simplified() == .percentOff(75, .nightly(100)))
        // 10% then 15% = 23.5%: not an Int, so it stays nested.
        #expect(Rule.percentOff(10, .percentOff(15, .nightly(100))).simplified() == .percentOff(10, .percentOff(15, .nightly(100))))
        #expect(Rule.ifStayAtLeast(nights: 5, then: .cleaningFee(10), else: .cleaningFee(10)).simplified() == .cleaningFee(10))
    }

    @Test func customPatternOperator() {
        #expect(E02.describe(nights: 3) == "short stay")
        #expect(E02.describe(nights: 7) == "weekly stay")
        #expect(E02.describe(nights: 30) == "monthly stay")
        #expect(E02.describe(nights: 0) == "invalid")
    }

    @Test func forCaseSumsCleaningFees() {
        #expect(E02.totalCleaningFees([.cleaningFee(10), .nightly(5), .cleaningFee(15)]) == 25)
    }
}

@Suite("Ex03 Optionals")
struct E03Tests {
    @Test func rhsNotEvaluatedWhenSome() {
        var calls = 0
        func fallback() -> Int { calls += 1; return 0 }

        #expect((E03.Maybe.some(5) |? fallback()) == 5)
        #expect(calls == 0)
        #expect((E03.Maybe<Int>.none |? fallback()) == 0)
        #expect(calls == 1)
    }

    @Test func mapAndFlatMap() {
        let price: E03.Maybe<Int> = .some(100)
        #expect(price.map { $0 * 2 } == .some(200))
        #expect(price.flatMap { $0 > 50 ? .some("expensive") : .none } == .some("expensive"))
        #expect(E03.Maybe<Int>.none.map { $0 * 2 } == .none)
    }

    @Test func flatMapFlattens() {
        let nested: E03.Maybe<E03.Maybe<Int>> = .some(.some(3))
        #expect(nested.flattened() == .some(3))
        let empty: E03.Maybe<E03.Maybe<Int>> = .some(.none)
        #expect(empty.flattened() == .none)
    }

    @Test func nilLiteral() {
        let value: E03.Maybe<Int> = nil
        #expect(value == .none)
        #expect(value.unwrapped(or: 7) == 7)
    }

    @Test func doubleOptional() {
        let overrides: [String: Int?] = ["price": nil, "guests": 2]
        #expect(E03.lookup(overrides, "price") == .explicitNil)
        #expect(E03.lookup(overrides, "guests") == .value(2))
        #expect(E03.lookup(overrides, "pets") == .missing)
    }
}

@Suite("Ex04 Dispatch")
struct E04Tests {
    struct Row: Sendable, CustomTestStringConvertible {
        let callSite: String
        let call: @Sendable () -> String
        let expected: String
        var testDescription: String { callSite }
    }

    static let rows: [Row] = [
        Row(callSite: "Listing concrete summary", call: { E04.Listing().summary() }, expected: "listing summary"),
        Row(callSite: "Listing concrete badge", call: { E04.Listing().badge() }, expected: "listing badge"),
        Row(callSite: "Listing generic summary", call: { E04.viaGeneric(E04.Listing()).summary }, expected: "listing summary"),
        Row(callSite: "Listing generic badge", call: { E04.viaGeneric(E04.Listing()).badge }, expected: "generic badge"),
        Row(callSite: "Listing any summary", call: { E04.viaExistential(E04.Listing()).summary }, expected: "listing summary"),
        Row(callSite: "Listing any badge", call: { E04.viaExistential(E04.Listing()).badge }, expected: "generic badge"),
        Row(callSite: "BaseCard concrete summary", call: { E04.BaseCard().summary() }, expected: "generic summary"),
        Row(callSite: "PremiumCard concrete summary", call: { E04.PremiumCard().summary() }, expected: "premium summary"),
        Row(callSite: "PremiumCard as BaseCard", call: { (E04.PremiumCard() as E04.BaseCard).summary() }, expected: "generic summary"),
        Row(callSite: "PremiumCard generic", call: { E04.viaGeneric(E04.PremiumCard()).summary }, expected: "generic summary"),
        Row(callSite: "PremiumCard any", call: { E04.viaExistential(E04.PremiumCard()).summary }, expected: "generic summary"),
        Row(callSite: "Fix 1 generic", call: { E04.viaGeneric(E04.FixedPremiumCard()).summary }, expected: "premium summary"),
        Row(callSite: "Fix 1 as base", call: { (E04.FixedPremiumCard() as E04.FixedBaseCard).summary() }, expected: "premium summary"),
        Row(callSite: "Fix 2 any", call: { E04.viaExistential(E04.ComposedPremiumCard()).summary }, expected: "premium summary"),
    ]

    @Test(arguments: rows)
    func dispatch(_ row: Row) {
        #expect(row.call() == row.expected)
    }
}

@Suite("Ex05 Module selectors")
struct E05Tests {
    @Test func convertsBetweenModules() {
        let pricing = E05.convert(Payments::Money(cents: 12_345, currency: "USD"))
        #expect(pricing == Pricing::Money(amount: Decimal(string: "123.45")!))
    }

    /// SE-0491 says `value.Module::member` selects that module's extension
    /// member. On Swift 6.3.2 AND 6.4.2 it compiles, but both selectors call the
    /// SAME extension (observed: "pay-loft" for both). Selectors on top-level
    /// names and on nested types (`Ship.A::Engine`) do work. `withKnownIssue`
    /// documents the bug and starts failing once a fixed compiler ships.
    @Test func memberSelectorPicksExtension() {
        let slugs = E05.slugs(for: "Loft")
        #expect(slugs.payments == "pay-loft")
        withKnownIssue("Member module selectors resolve to the wrong extension (Swift 6.3.2 / 6.4.2)") {
            #expect(slugs.pricing == "price-loft")
        }
    }

    @Test func topLevelVsNested() {
        let checkout = E05.Checkout()
        #expect(checkout.nestedMoney().nested)
        #expect(checkout.topLevelMoney().label == "top-level")
    }

    @Test func moduleAndTypeWithTheSameName() {
        #expect(E05.importedListing(title: "Imported").title == "Imported")
        #expect(E05.localListing(title: "Local").title == "Local")
    }
}

@Suite("Ex06 Copy-on-write")
struct E06Tests {
    @Test func copySharesStorage() {
        let a = AvailabilityCalendar(price: 100)
        let b = a
        #expect(a._storageID == b._storageID)
    }

    @Test func mutationUnshares() {
        let a = AvailabilityCalendar(price: 100)
        var b = a
        b.block(0..<3)
        #expect(a._storageID != b._storageID)
        #expect(a.availableDays == 365)
        #expect(b.availableDays == 362)
    }

    @Test func uniqueMutationDoesNotReallocate() {
        var calendar = AvailabilityCalendar(price: 100)
        let id = calendar._storageID
        calendar[3].price += 10
        calendar.block(0..<10)
        #expect(calendar._storageID == id)
        #expect(calendar[3].price == 110)
    }

    @Test func snapshotPerMutationCopiesEveryTime() {
        var calendar = AvailabilityCalendar(days: 50, price: 100)
        let result = E06.repriceWithHistory(&calendar, to: 80)
        #expect(result.copies == 50)                    // one full copy per iteration: O(n²)
        #expect(result.history.first?[0].price == 100)  // history is intact
        #expect(calendar[49].price == 80)
    }

    @Test func bulkRepriceKeepsSnapshotsIntact() {
        var calendar = AvailabilityCalendar(price: 100)
        let snapshot = calendar
        E06.repriceFast(&calendar, to: 80)
        #expect(snapshot[0].price == 100)
        #expect(calendar[364].price == 80)
    }

    @Test func manyUniqueMutationsAreFast() {
        var calendar = AvailabilityCalendar(price: 100)
        let elapsed = ContinuousClock().measure {
            for i in 0..<100_000 { calendar[i % 365].price += 1 }
        }
        // Generous bound for a debug build on CI; release is ~100× faster.
        #expect(elapsed < .seconds(2))
    }
}
