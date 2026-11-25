// The contract: every test below runs against BOTH pipelines. If a Combine pipeline
// and its AsyncSequence rewrite pass the same file, the migration preserved behavior.
//
// AC-1  Rapid typing is coalesced into one search for the last text.
// AC-2  Every keystroke restarts the debounce timer.
// AC-3  A query equal to the previous one (after trimming) does not search again.
// AC-4  A blank query clears the results without calling the service.
// AC-5  A slow response for a superseded query is never emitted.
// AC-6  A superseded search is cancelled, not just ignored.
// AC-7  A failing search is reported, and the pipeline keeps working.
// AC-8  Tearing the pipeline down cancels the search in flight.

import Testing
@testable import CombineSearch

@MainActor
@Suite("Search contract: Combine vs AsyncSequence", .serialized)
struct SearchContractTests {
    func hits(_ query: String) -> [Hit] { [Hit(id: 1, title: "Stay for \(query)")] }

    @Test("AC-1 rapid typing is coalesced", arguments: Implementation.allCases)
    func coalescesRapidTyping(_ implementation: Implementation) async {
        let harness = implementation.makeHarness()
        for text in ["p", "pa", "par", "pari", "paris"] { await harness.type(text) }
        await harness.advance(milliseconds: 300)

        let outputs = await harness.outputs(count: 1)
        #expect(outputs == [.results(query: "paris", hits: hits("paris"))])
        #expect(await harness.service.queries == ["paris"])
        await harness.shutdown()
    }

    @Test("AC-2 each keystroke restarts the timer", arguments: Implementation.allCases)
    func keystrokeRestartsTimer(_ implementation: Implementation) async {
        let harness = implementation.makeHarness()
        await harness.type("p")
        await harness.advance(milliseconds: 200)
        await harness.type("pa")
        await harness.advance(milliseconds: 200)            // 400 ms since "p", only 200 since "pa"
        #expect(harness.emitted.isEmpty)
        #expect(await harness.service.queries.isEmpty)

        await harness.advance(milliseconds: 100)            // 300 ms since "pa"
        let outputs = await harness.outputs(count: 1)
        #expect(outputs == [.results(query: "pa", hits: hits("pa"))])
        await harness.shutdown()
    }

    @Test("AC-3 an unchanged query does not search again", arguments: Implementation.allCases)
    func ignoresDuplicates(_ implementation: Implementation) async {
        let harness = implementation.makeHarness()
        await harness.type("paris")
        await harness.advance(milliseconds: 300)
        _ = await harness.outputs(count: 1)

        await harness.type("paris  ")                       // same query once trimmed
        await harness.advance(milliseconds: 300)
        await harness.type("rome")                          // a later output proves nothing slipped in between
        await harness.advance(milliseconds: 300)

        let outputs = await harness.outputs(count: 2)
        #expect(outputs == [
            .results(query: "paris", hits: hits("paris")),
            .results(query: "rome", hits: hits("rome")),
        ])
        #expect(await harness.service.queries == ["paris", "rome"])
        await harness.shutdown()
    }

    @Test("AC-4 a blank query clears results without a service call", arguments: Implementation.allCases)
    func blankQueryClears(_ implementation: Implementation) async {
        let harness = implementation.makeHarness()
        await harness.type("paris")
        await harness.advance(milliseconds: 300)
        _ = await harness.outputs(count: 1)

        await harness.type("   ")
        await harness.advance(milliseconds: 300)

        let outputs = await harness.outputs(count: 2)
        #expect(outputs.last == .results(query: "", hits: []))
        #expect(await harness.service.queries == ["paris"])
        await harness.shutdown()
    }

    @Test("AC-5 a stale response is never emitted", arguments: Implementation.allCases)
    func staleResponseDropped(_ implementation: Implementation) async {
        let harness = implementation.makeHarness()
        await harness.service.script("a", .held)

        await harness.type("a")
        await harness.advance(milliseconds: 300)
        await harness.service.waitForQueries(1)              // "a" is now in flight

        await harness.type("ab")
        await harness.advance(milliseconds: 300)
        _ = await harness.outputs(count: 1)                  // "ab" answered first

        await harness.service.release("a", with: [Hit(id: 99, title: "STALE")])
        await harness.type("abc")                            // a later output proves "a" did not sneak in
        await harness.advance(milliseconds: 300)

        let outputs = await harness.outputs(count: 2)
        #expect(outputs == [
            .results(query: "ab", hits: hits("ab")),
            .results(query: "abc", hits: hits("abc")),
        ])
        await harness.shutdown()
    }

    @Test("AC-6 a superseded search is cancelled", arguments: Implementation.allCases)
    func supersededSearchCancelled(_ implementation: Implementation) async {
        let harness = implementation.makeHarness()
        await harness.service.script("a", .held)

        await harness.type("a")
        await harness.advance(milliseconds: 300)
        await harness.service.waitForQueries(1)

        await harness.type("ab")
        await harness.advance(milliseconds: 300)

        await harness.service.waitUntilCancelled("a")        // would hang if "a" were only ignored
        #expect(await harness.service.cancelled == ["a"])
        await harness.shutdown()
    }

    @Test("AC-7 a failure is reported and the pipeline survives", arguments: Implementation.allCases)
    func failureThenRecovery(_ implementation: Implementation) async {
        let harness = implementation.makeHarness()
        await harness.service.script("boom", .failure)

        await harness.type("boom")
        await harness.advance(milliseconds: 300)
        _ = await harness.outputs(count: 1)                  // let "boom" finish: typing again would supersede it
        await harness.type("ok")
        await harness.advance(milliseconds: 300)

        let outputs = await harness.outputs(count: 2)
        #expect(outputs == [
            .failed(query: "boom", message: "search failed"),
            .results(query: "ok", hits: hits("ok")),
        ])
        await harness.shutdown()
    }

    @Test("AC-8 teardown cancels the search in flight", arguments: Implementation.allCases)
    func teardownCancelsInFlight(_ implementation: Implementation) async {
        let harness = implementation.makeHarness()
        await harness.service.script("a", .held)

        await harness.type("a")
        await harness.advance(milliseconds: 300)
        await harness.service.waitForQueries(1)

        await harness.shutdown()
        await harness.service.waitUntilCancelled("a")
        #expect(harness.emitted.isEmpty)
    }
}
