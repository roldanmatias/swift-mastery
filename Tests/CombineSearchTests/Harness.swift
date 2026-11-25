// One test driver, two implementations. The contract tests only talk to `SearchHarness`,
// so "Combine and AsyncSequence behave the same" is checked by running the very same
// test bodies against both.

import Combine
import Concurrency
import Synchronization
import Testing
@testable import CombineSearch

@MainActor
protocol SearchHarness: AnyObject {
    var service: FakeSearchService { get }
    /// What the user types into the search box.
    func type(_ text: String) async
    /// Moves time forward and lets the debounce timers that come due fire.
    func advance(milliseconds: Int) async
    /// Suspends until `count` outputs have been emitted, then returns all of them.
    func outputs(count: Int) async -> [SearchOutput]
    /// Outputs emitted so far, without waiting.
    var emitted: [SearchOutput] { get }
    /// Tears the pipeline down (the view went away).
    func shutdown() async
}

enum Implementation: String, CaseIterable, CustomTestStringConvertible, Sendable {
    case combine, asyncSequence
    var testDescription: String { rawValue }

    @MainActor
    func makeHarness() -> any SearchHarness {
        switch self {
        case .combine: CombineHarness()
        case .asyncSequence: AsyncHarness()
        }
    }
}

// MARK: - Combine

@MainActor
final class CombineHarness: SearchHarness {
    let service = FakeSearchService()
    private let scheduler = ManualScheduler()
    private let recorder = OutputRecorder()
    private let pipeline: CombineSearchPipeline<ManualScheduler>
    private var subscription: AnyCancellable?

    init() {
        pipeline = CombineSearchPipeline(service: service, scheduler: scheduler)
        subscription = pipeline.outputs.sink { [recorder] in recorder.record($0) }
    }

    func type(_ text: String) async { pipeline.input.send(text) }

    func advance(milliseconds: Int) async {
        // The debounce timer is registered synchronously by `send`, so time can move now.
        scheduler.advance(by: .milliseconds(milliseconds))
    }

    func outputs(count: Int) async -> [SearchOutput] {
        await recorder.waitForOutputs(count)
        return recorder.outputs
    }

    var emitted: [SearchOutput] { recorder.outputs }

    func shutdown() async { subscription = nil }   // dropping the AnyCancellable cancels the chain
}

// MARK: - AsyncSequence

/// A clock that counts how many times someone started sleeping on it. The async debounce
/// registers its timer from another task, so after `type` the test needs a way to know
/// the timer *exists* before moving time. A plain "is anyone sleeping?" check would be
/// satisfied by the previous, about-to-be-cancelled timer.
final class CountingClock: Clock, Sendable {
    typealias Instant = ManualClock.Instant
    typealias Duration = Swift.Duration

    let base = ManualClock()
    private let state = Mutex((sleeps: 0, waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)]()))

    var now: Instant { base.now }
    var minimumResolution: Duration { base.minimumResolution }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let ready: [CheckedContinuation<Void, Never>] = state.withLock { state in
            state.sleeps += 1
            let n = state.sleeps
            let ready = state.waiters.filter { $0.count <= n }.map(\.continuation)
            state.waiters.removeAll { $0.count <= n }
            return ready
        }
        ready.forEach { $0.resume() }
        try await base.sleep(until: deadline, tolerance: tolerance)
    }

    func waitForSleeps(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done = state.withLock { state in
                if state.sleeps >= count { return true }
                state.waiters.append((count, continuation))
                return false
            }
            if done { continuation.resume() }
        }
    }
}

@MainActor
final class AsyncHarness: SearchHarness {
    let service = FakeSearchService()
    private let clock = CountingClock()
    private let recorder = OutputRecorder()
    private let input: AsyncStream<String>.Continuation
    private let consumer: Task<Void, Never>
    private var typed = 0

    init() {
        let (queries, input) = AsyncStream.makeStream(of: String.self)
        self.input = input
        let pipeline = AsyncSearchPipeline(service: service, clock: clock)
        let recorder = recorder
        let outputs = pipeline.outputs(for: queries)
        consumer = Task { for await output in outputs { recorder.record(output) } }
    }

    func type(_ text: String) async {
        input.yield(text)
        typed += 1
        // Wait until the debounce stage has consumed this element and started its timer.
        await clock.waitForSleeps(typed)
    }

    func advance(milliseconds: Int) async {
        await clock.base.waitForSleepers(1)
        clock.base.advance(by: .milliseconds(milliseconds))
    }

    func outputs(count: Int) async -> [SearchOutput] {
        await recorder.waitForOutputs(count)
        return recorder.outputs
    }

    var emitted: [SearchOutput] { recorder.outputs }

    func shutdown() async {
        input.finish()
        consumer.cancel()        // cancelling the consumer ends the stream chain and cancels in-flight work
    }
}
