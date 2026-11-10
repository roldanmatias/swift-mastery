// Tests for Ex 07–10 (functions and closures).

import Foundation
import Testing
@testable import Language

@Suite("Ex07 inout and exclusivity")
struct E07Tests {
    @Test func applyDiscount() {
        var price: Decimal = 200
        E07.applyDiscount(&price, percent: 25)
        #expect(price == 150)
    }

    /// Copy-in/copy-out: three mutations of the callee's copy, ONE write-back.
    @Test func didSetFiresOnce() {
        var listing = E07.Listing(nightlyPrice: 100)
        E07.bumpThreeTimes(&listing.nightlyPrice)
        #expect(listing.nightlyPrice == 103)
        #expect(listing.didSetCount == 1)
    }

    /// Exit test: runs the body in a child process and expects it to crash.
    @Test func exclusivityViolationTraps() async {
        await #expect(processExitsWith: .failure) {
            E07.triggerExclusivityViolation()
        }
    }

    @Test func distinctPropertiesOfALocalStructDontOverlap() {
        let stay = E07.balanceLocalStay()
        #expect(stay.nights == 3)
        #expect(stay.guests == 3)
    }
}

@Suite("Ex08 Escaping closures and capture lists")
struct E08Tests {
    private func isDeallocated(after start: (E08.ListingDetailModel) -> Void) -> Bool {
        weak var weakModel: E08.ListingDetailModel?
        do {
            let model = E08.ListingDetailModel(loader: E08.ImageLoader())
            start(model)
            weakModel = model
        }
        return weakModel == nil
    }

    @Test func leakingStartLeaks() {
        #expect(isDeallocated { $0.startLeaking() } == false)
    }

    @Test func weakSelfFixesTheCycle() {
        #expect(isDeallocated { $0.startWeak() })
    }

    @Test func unownedSelfFixesTheCycle() {
        #expect(isDeallocated { $0.startUnowned() })
    }

    @Test func capturingValuesFixesTheCycle() {
        #expect(isDeallocated { _ = $0.startCapturingValues() })
    }

    @Test func weakSelfStillDelivers() {
        let model = E08.ListingDetailModel(loader: E08.ImageLoader())
        model.startWeak()
        model.loader.finishAll(with: Data([1, 2]))
        #expect(model.imageData == Data([1, 2]))
    }

    @Test func captureListSnapshotsTheValue() {
        let model = E08.ListingDetailModel(loader: E08.ImageLoader())
        model.title = "Loft"
        let message = model.startCapturingValues()
        model.title = "Studio"
        #expect(message() == "Loading Loft")
    }

    @Test func captureByReferenceVsSnapshot() {
        let result = E08.captureSemantics()
        #expect(result.byReference == 200)
        #expect(result.snapshot == 100)
    }

    @Test func withoutActuallyEscaping() {
        #expect(E08.countMatches([1, 2, 3, 4], where: { $0.isMultiple(of: 2) }) == 2)
    }
}

@Suite("Ex09 Key paths")
struct E09Tests {
    let a = E09.Listing(title: "A", rating: 4.8, nightlyPrice: 120)
    let b = E09.Listing(title: "B", rating: 4.8, nightlyPrice: 90)
    let c = E09.Listing(title: "C", rating: 4.2, nightlyPrice: 60)

    @Test func sortBySingleKeyPath() {
        #expect([a, b, c].sorted(by: \.nightlyPrice).map(\.title) == ["C", "B", "A"])
        #expect([a, b, c].sorted(by: \.nightlyPrice, ascending: false).map(\.title) == ["A", "B", "C"])
    }

    @Test func multiKeySortBreaksTies() {
        let sorted = [a, c, b].sorted(by: [.init(\.rating, ascending: false), .init(\.nightlyPrice)])
        #expect(sorted.map(\.title) == ["B", "A", "C"])
    }

    @Test func updatingDoesNotMutateOriginal() {
        let renamed = E09.updating(a, \.title, to: "Z")
        #expect(a.title == "A")
        #expect(renamed.title == "Z")
    }

    @Test func appendedKeyPath() {
        #expect(a[keyPath: E09.hostName] == "Ana")
        #expect(E09.hostName == \E09.Listing.host.name)
        #expect(b[keyPath: E09.titlePath] == "B")
    }

    @Test func keyPathAsFunction() {
        #expect([a, b].map(\.title) == ["A", "B"])
    }

    @Test func referenceWritableKeyPath() {
        let draft = E09.Draft()
        E09.setTitle(draft, \.title, "New")
        #expect(draft.title == "New")
    }
}

@Suite("Ex10 Lazy sequences")
struct E10Tests {
    @Test func stayNightsAreDSTSafe() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // US DST starts Sunday 2026-03-08.
        let checkIn = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7)))
        let checkOut = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)))

        let nights = Array(E10.StayNights(checkIn: checkIn, checkOut: checkOut, calendar: calendar))
        #expect(nights.count == 3)
        #expect(nights.allSatisfy { calendar.component(.hour, from: $0) == 0 })

        // The naive approach drifts to 1 AM after the DST change:
        let naive = checkIn.addingTimeInterval(2 * 86_400)
        #expect(calendar.component(.hour, from: naive) == 1)
    }

    @Test func lazyEvaluatesOnlyWhatsNeeded() {
        var filterCalls = 0
        var mapCalls = 0
        let result = Array(
            E10.PriceSeries()                       // infinite: eager filter would never return
                .lazy
                .filter { filterCalls += 1; return $0 > 100 }
                .map { mapCalls += 1; return $0 * 2 }
                .prefix(4)
        )
        #expect(result == [250, 250, 250, 250])
        #expect(filterCalls == 14)                  // days 0…13 (weekends are 5,6,12,13)
        #expect(mapCalls == 4)
    }

    @Test func lazyIsNotCached() {
        var calls = 0
        let pipeline = [1, 2, 3].lazy.map { calls += 1; return $0 * 2 }
        _ = Array(pipeline)
        _ = Array(pipeline)
        #expect(calls == 6)                         // re-runs on every iteration
    }

    @Test func chunkedStaysLazy() {
        #expect(Array([1, 2, 3, 4, 5].lazy.chunked(by: 2)) == [[1, 2], [3, 4], [5]])
        let weeks = Array(E10.PriceSeries().lazy.chunked(by: 7).prefix(2))   // infinite input
        #expect(weeks.count == 2)
        #expect(weeks[0] == [100, 100, 100, 100, 100, 125, 125])
    }
}
