// Tests for Ex 11–16 (protocols and generics).

import Foundation
import Testing
@testable import Language

@Suite("Ex11 Associated and primary associated types")
struct E11Tests {
    /// One generic contract, run against every implementation.
    func exercise<R: E11.Repository<Listing>>(_ repository: inout R) {
        let a = Listing(title: "A", nightlyPrice: 100)
        let b = Listing(title: "B", nightlyPrice: 50)
        repository.upsert(a)
        repository.upsert(b)
        #expect(repository.all().count == 2)
        #expect(repository.find(a.id)?.title == "A")

        var renamed = a
        renamed.title = "A2"
        repository.upsert(renamed)
        #expect(repository.all().count == 2)
        #expect(repository.find(a.id)?.title == "A2")
        #expect(repository.find(ListingID(UUID())) == nil)
    }

    @Test func inMemoryKeepsInsertionOrder() {
        var repository = E11.InMemoryRepository<Listing>()
        exercise(&repository)
        #expect(repository.all().map(\.title) == ["A2", "B"])
    }

    @Test func sortedKeepsPriceOrder() {
        var repository = E11.SortedRepository<Listing>()
        exercise(&repository)
        #expect(repository.all().map(\.title) == ["B", "A2"])
    }

    @Test func opaqueRepository() {
        var repository = E11.makeListingRepository()
        exercise(&repository)
        // Callers only know "some Collection of Listing", not Array:
        let all = repository.all()
        #expect(all.map(\.title).count == 2)
    }

    @Test func constrainedExtensions() {
        let repository = E11.InMemoryRepository([
            Listing(title: "A", city: "Rosario", nightlyPrice: 10),
            Listing(title: "B", city: "Rosario", nightlyPrice: 20),
            Listing(title: "C", city: "Córdoba", nightlyPrice: 30),
        ])
        #expect(repository.duplicates(by: \.city).keys.sorted() == ["Rosario"])
        #expect(repository.entitySet().count == 3)
    }
}

@Suite("Ex12 some vs any")
struct E12Tests {
    @Test(arguments: E12.Season.allCases)
    func someAndAnyAgree(_ season: E12.Season) {
        #expect(E12.someStrategy(for: season).price(nights: 7) == E12.anyStrategy(for: season).price(nights: 7))
    }

    @Test func cheapestOfHeterogeneousStrategies() {
        let strategies: [any E12.PricingStrategy] = E12.Season.allCases.map(E12.anyStrategy(for:))
        #expect(E12.cheapest(strategies, nights: 7) == 560)
    }

    @Test func implicitOpening() {
        #expect(E12.auditExistential(E12.anyStrategy(for: .high)) == "WeeklyDiscount")
        #expect(E12.auditExistential(E12.anyStrategy(for: .holiday)) == "SurgePricing")
    }

    @Test func someParameterEqualsGeneric() {
        let strategy = E12.StandardPricing(nightly: 80)
        #expect(E12.quote(strategy, nights: 3) == E12.quoteGeneric(strategy, nights: 3))
    }

    @Test func memoryLayout() {
        // 3-word inline value buffer + type metadata + 1 witness table = 5 words.
        #expect(MemoryLayout<any E12.PricingStrategy>.size == 40)
        // Optional existential reuses spare bits/extra inhabitants: no extra byte.
        #expect(MemoryLayout<(any E12.PricingStrategy)?>.size == 40)
        // Class-constrained: just the reference + witness table.
        #expect(MemoryLayout<any E12.PricingStrategy & AnyObject>.size == 16)
        // The concrete type is just its stored Decimal (20 bytes): no box.
        #expect(MemoryLayout<E12.StandardPricing>.size == MemoryLayout<Decimal>.size)
    }

    @Test func erasedRepository() {
        var repository: any E11.Repository<Listing> = E11.InMemoryRepository<Listing>()
        E12.erasedRepositoryUpsert(&repository, Listing(title: "A", nightlyPrice: 10))
        #expect(E12.erasedRepositoryCount(repository) == 1)
    }

    @Test func optionalShorthand() {
        #expect(E12.optionalQuote(nil, nights: 3) == nil)
        #expect(E12.optionalQuote(E12.StandardPricing(nightly: 10), nights: 3) == 30)
    }

    @Test func optionalConformanceIsATrap() {
        let missing: E12.StandardPricing? = nil
        let price: Decimal = missing.price(nights: 3)
        #expect(price == 0)   // a free stay: the reason not to ship this
    }
}

@Suite("Ex13 Generic constraints")
struct E13Tests {
    @Test func constrainedExtensions() {
        #expect([1, 2, 3].sum() == 6)
        #expect(([1.5, 2.5] as [Double]).sum() == 4)
        let listings = [Listing(title: "A", nightlyPrice: 100), Listing(title: "B", nightlyPrice: 50)]
        #expect(listings.averagePrice() == 75)
        #expect(E13.mergeUnique([1, 2, 3], [3, 4, 1]) == [1, 2, 3, 4])
    }

    @Test func directCallPicksMostSpecificOverload() {
        #expect([5, 1, 3].median().strategy == "RandomAccessCollection")
        #expect([5, 1, 3].median().value == 3)
        #expect(Set([5, 1, 3]).median().strategy == "Collection")
    }

    @Test func genericContextPicksCollectionOverload() {
        #expect(E13.report([5, 1, 3]).strategy == "Collection")   // the trap
    }

    @Test func customizationPointDispatchesDynamically() {
        #expect(E13.reportFixed([5, 1, 3]).strategy == "RandomAccessCollection")
        #expect(E13.reportFixed(Set([5, 1, 3])).strategy == "Collection")
        #expect(E13.reportFixed([5, 1, 3]).value == 3)
    }
}

@Suite("Ex14 Conditional conformance and phantom types")
struct E14Tests {
    let id = ListingID(UUID(uuidString: "5F1B6C1E-0000-0000-0000-000000000001")!)

    @Test func hashable() {
        var ids: Set<ListingID> = [id]
        ids.insert(id)
        #expect(ids.count == 1)
    }

    @Test func encodesAsBareRawValue() throws {
        let data = try JSONEncoder().encode(id)
        #expect(String(decoding: data, as: UTF8.self) == "\"5F1B6C1E-0000-0000-0000-000000000001\"")
        #expect(try JSONDecoder().decode(ListingID.self, from: data) == id)
    }

    @Test func literals() {
        let numeric: Tagged<Listing, Int> = 42
        // `Host` alone is ambiguous here: Foundation (macOS) also has a `Host`
        // class. A module selector picks ours: a real-world Ex 05 case.
        let named: Tagged<Language::Host, String> = "ana"
        #expect(numeric.rawValue == 42)
        #expect(named.rawValue == "ana")
        #expect([3, 1, 2].map { Tagged<Listing, Int>($0) }.sorted().map(\.rawValue) == [1, 2, 3])
    }

    @Test func phantomTypeIsFree() {
        #expect(E14.taggedIsFree)
    }

    struct NotHashable {}

    @Test func conditionalConformanceAtRuntime() {
        #expect((id as Any) as? any Hashable != nil)
        #expect((Tagged<Listing, NotHashable>(NotHashable()) as Any) as? any Hashable == nil)
    }
}

@Suite("Ex15 Type erasure")
struct E15Tests {
    @Test func erasedSinksAreHashableByIdentity() {
        let recorder = E15.RecordingSink()
        let sinks: Set<E15.AnyEventSink<E15.BookingEvent>> = [
            E15.AnyEventSink(recorder), E15.AnyEventSink(recorder), E15.AnyEventSink(E15.RecordingSink()),
        ]
        #expect(sinks.count == 2)
    }

    @Test func allStrategiesDispatchToTheSink() {
        let recorder = E15.RecordingSink()
        E15.AnyEventSink(recorder).send(.held("a"))
        var boxed = E15.BoxedEventSink(recorder)
        boxed.send(.confirmed("a"))
        var existentials: [any E15.EventSink<E15.BookingEvent>] = [recorder]
        E15.fanOut(&existentials, .cancelled("a"))
        #expect(recorder.events == [.held("a"), .confirmed("a"), .cancelled("a")])
    }

    @Test func closureEraserSharesStructState() {
        var reports: [Int] = []
        let a = E15.AnyEventSink(E15.CountingSink { reports.append($0) })
        let b = a
        a.send(.held("x"))
        b.send(.held("x"))
        #expect(reports == [1, 2])   // reference semantics: one shared counter
    }

    @Test func boxEraserWithCoWKeepsValueSemantics() {
        var reports: [Int] = []
        var a = E15.BoxedEventSink(E15.CountingSink { reports.append($0) })
        var b = a
        a.send(.held("x"))
        b.send(.held("x"))
        #expect(reports == [1, 1])   // each copy has its own counter
        #expect(a.unwrap(as: E15.CountingSink.self)?.count == 1)
    }

    @Test func existentialKeepsValueSemantics() {
        var reports: [Int] = []
        let original: [any E15.EventSink<E15.BookingEvent>] = [E15.CountingSink { reports.append($0) }]
        var first = original
        var second = original
        E15.fanOut(&first, .held("x"))
        E15.fanOut(&second, .held("x"))
        #expect(reports == [1, 1])
    }
}

@Suite("Ex16 Parameter packs")
struct E16Tests {
    @Test func allPresent() {
        let single: Int? = E16.allPresent(5)                   // arity 1: the "tuple" is just Int
        #expect(single == 5)
        let pair = E16.allPresent(1, "a")
        #expect(pair?.0 == 1 && pair?.1 == "a")
        let triple = E16.allPresent(1, "a", true)
        #expect(triple?.2 == true)
        #expect(E16.allPresent(1, nil as String?, 3.0) == nil)
        let five = E16.allPresent(1, 2, 3, 4, "five")
        #expect(five?.4 == "five")
    }

    @Test func zipAll() {
        let two = E16.zipAll([1, 2, 3], ["a", "b"])
        #expect(two.count == 2)
        #expect(two[0] == (1, "a"))
        let one = E16.zipAll([1, 2])
        #expect(one == [1, 2])
        let three = E16.zipAll([1, 2], ["x", "y"], [true, false])
        #expect(three[1] == (2, "y", false))
        let five = E16.zipAll([1, 2], [3, 4], [5, 6], [7, 8], [9, 10])
        #expect(five.count == 2)
        #expect(five[1] == (2, 4, 6, 8, 10))
    }

    @Test func formValidator() {
        let validator = E16.FormValidator(
            E16.Rule<String>(name: "title") { !$0.isEmpty },
            E16.Rule<Int>(name: "guests") { (1...16).contains($0) },
            E16.Rule<Decimal>(name: "price") { $0 > 0 }
        )
        #expect(validator.failures("", 20, 99) == ["title", "guests"])
        #expect(validator.failures("Loft", 2, 99).isEmpty)
        #expect(validator.failures("Loft", 2, 0) == ["price"])
    }

    @Test func packIteration() {
        #expect(E16.describeAll(1, "x", 2.5) == ["1", "x", "2.5"])
        #expect(E16.count(1, "two", 3.0, [4]) == 4)
    }
}
