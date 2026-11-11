// Tests for C09–C12 (the ConcurrencyApp target: default MainActor isolation +
// nonisolated(nonsending) by default). This test target itself uses Swift 6 defaults.

import Foundation
import Testing
@testable import ConcurrencyApp

@Suite("C09 Default MainActor isolation")
struct C09Tests {
    @MainActor @Test func unannotatedTypesAreMainActorIsolated() {
        let model = SearchModel()
        model.update(query: "lisbon", results: [ListingDTO(id: 1, title: "Loft", nightlyCents: 12_000)])
        #expect(model.query == "lisbon")
        #expect(model.rows == [ListingRow(ListingDTO(id: 1, title: "Loft", nightlyCents: 12_000))])
        #expect(model.rows.first?.priceText == "$120")
        #expect(isOnMainActor())
    }

    @Test func nonisolatedTypesWorkOffTheMainActor() async throws {
        #expect(isOnMainActor() == false)
        let json = Data(#"[{"id":1,"title":"Loft","nightlyCents":12000}]"#.utf8)
        let dtos = try JSONDecoder().decode([ListingDTO].self, from: json)   // nonisolated conformance
        #expect(dtos.map(\.id) == [1])
        #expect(PriceMath.average([100, 200, 300]) == 200)
    }
}

@Suite("C10 nonisolated(nonsending) vs @concurrent")
struct C10Tests {
    @MainActor @Test func asyncFunctionsInheritTheCallersActor() async {
        #expect(await ExecutionProbe.inheritsCaller())
        #expect(await ExecutionProbe.explicitlyNonsending())
        #expect(await ExecutionProbe.nonsendingRunsOnMainThread())
    }

    @MainActor @Test func concurrentAlwaysLeaves() async {
        #expect(await ExecutionProbe.alwaysOffActor() == false)
        #expect(await ExecutionProbe.concurrentRunsOnMainThread() == false)
    }

    @Test func fromANonisolatedCallerThereIsNoActorToInherit() async {
        #expect(await ExecutionProbe.inheritsCaller() == false)
    }
}

@Suite("C11 Offloading work")
struct C11Tests {
    @MainActor @Test func decodingRunsOffTheMainThread() async throws {
        let payload = try ListingDecoder.makePayload(count: 10_000)
        let (dtos, onMainThread) = try await ListingDecoder.decodeReportingThread(payload)
        #expect(dtos.count == 10_000)
        #expect(onMainThread == false)
    }

    @MainActor @Test func loaderAppliesResultsOnTheMainActor() async throws {
        let model = SearchModel()
        let loader = SearchLoader(model: model)
        try await loader.load(query: "porto", payload: ListingDecoder.makePayload(count: 50))
        #expect(model.rows.count == 50)
        #expect(model.query == "porto")
    }
}

@Suite("C12 isolated deinit and Task.immediate")
@MainActor
struct C12Tests {
    @Test func isolatedDeinitRunsOnTheMainActor() {
        let id = Int.random(in: 1_000_000...9_999_999)
        do {
            let session = PhotoUploadSession(id: id)
            #expect(UploadRegistry.shared.active.contains(session.id))
        }
        // Last release happened on the main actor, so the isolated deinit ran inline.
        #expect(!UploadRegistry.shared.active.contains(id))
    }

    @Test func isolatedDeinitIsEnqueuedWhenReleasedElsewhere() async {
        let id = Int.random(in: 1_000_000...9_999_999)
        var session: PhotoUploadSession? = PhotoUploadSession(id: id)
        let task = Task.detached { [session] in withExtendedLifetime(session) {} }   // last reference dies off-main
        session = nil
        await task.value
        var yields = 0
        while UploadRegistry.shared.active.contains(id), yields < 10_000 { await Task.yield(); yields += 1 }
        #expect(!UploadRegistry.shared.active.contains(id))
    }

    @Test func immediateTasksStartSynchronously() async {
        let log = EventLog()
        let task = log.startImmediate()
        #expect(log.events == ["immediate: started"])        // ran before we suspended
        await task.value
        #expect(log.events == ["immediate: started", "immediate: resumed"])
    }

    @Test func regularTasksAreOnlyEnqueued() async {
        let log = EventLog()
        let task = log.startEnqueued()
        #expect(log.events.isEmpty)                          // hasn't started yet
        await task.value
        #expect(log.events == ["enqueued: started"])
    }
}
