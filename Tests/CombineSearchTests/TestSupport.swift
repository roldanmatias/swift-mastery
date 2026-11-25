// Deterministic test doubles for the search pipelines. No test sleeps: time moves
// only when a test says so, and tests wait on events, never on durations.

import Combine
import Concurrency
import Synchronization
@testable import CombineSearch

// MARK: - Output recorder

/// Records pipeline outputs and lets a test wait for "the Nth output has arrived".
final class OutputRecorder: Sendable {
    private struct State {
        var outputs: [SearchOutput] = []
        var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }
    private let state = Mutex(State())

    func record(_ output: SearchOutput) {
        let ready: [CheckedContinuation<Void, Never>] = state.withLock { state in
            state.outputs.append(output)
            let n = state.outputs.count
            let ready = state.waiters.filter { $0.count <= n }.map(\.continuation)
            state.waiters.removeAll { $0.count <= n }
            return ready
        }
        ready.forEach { $0.resume() }
    }

    var outputs: [SearchOutput] { state.withLock { $0.outputs } }

    func waitForOutputs(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done = state.withLock { state in
                if state.outputs.count >= count { return true }
                state.waiters.append((count, continuation))
                return false
            }
            if done { continuation.resume() }
        }
    }
}

// MARK: - Fake service

struct SearchFailure: Error, CustomStringConvertible {
    var description: String { "search failed" }
}

/// A scripted `SearchService`. Each query is answered immediately, fails, or is *held*
/// until the test releases it, which is how tests control the order responses arrive in.
actor FakeSearchService: SearchService {
    enum Script { case hits([Hit]), failure, held }

    private var scripts: [String: Script] = [:]
    private var held: [String: CheckedContinuation<[Hit], any Error>] = [:]
    private(set) var queries: [String] = []
    private(set) var cancelled: [String] = []
    private var queryWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var cancelWaiters: [(query: String, continuation: CheckedContinuation<Void, Never>)] = []

    func script(_ query: String, _ script: Script) { scripts[query] = script }

    /// Default answer: one hit titled after the query.
    private func response(for query: String) -> Script {
        scripts[query] ?? .hits([Hit(id: 1, title: "Stay for \(query)")])
    }

    func search(_ query: String) async throws -> [Hit] {
        queries.append(query)
        let n = queries.count
        queryWaiters.filter { $0.count <= n }.forEach { $0.continuation.resume() }
        queryWaiters.removeAll { $0.count <= n }

        switch response(for: query) {
        case .hits(let hits): return hits
        case .failure: throw SearchFailure()
        case .held:
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { held[query] = $0 }
            } onCancel: {
                // `onCancel` is nonisolated and synchronous; hop onto the actor to record it.
                Task { await self.markCancelled(query) }
            }
        }
    }

    /// Completes a held query with `hits`.
    func release(_ query: String, with hits: [Hit]) {
        held.removeValue(forKey: query)?.resume(returning: hits)
    }

    private func markCancelled(_ query: String) {
        cancelled.append(query)
        cancelWaiters.filter { $0.query == query }.forEach { $0.continuation.resume() }
        cancelWaiters.removeAll { $0.query == query }
        held.removeValue(forKey: query)?.resume(throwing: CancellationError())
    }

    func waitForQueries(_ count: Int) async {
        if queries.count >= count { return }
        await withCheckedContinuation { queryWaiters.append((count, $0)) }
    }

    func waitUntilCancelled(_ query: String) async {
        if cancelled.contains(query) { return }
        await withCheckedContinuation { cancelWaiters.append((query, $0)) }
    }
}

// MARK: - Manual Combine scheduler

/// A Combine `Scheduler` whose time only moves on `advance(by:)`. Combine's own
/// schedulers (`DispatchQueue`, `RunLoop`) use real time, so `debounce` tests would sleep.
@MainActor
final class ManualScheduler {
    struct Time: Strideable, Hashable, Codable, Sendable {
        typealias Stride = Interval
        var offset: Int   // nanoseconds
        func distance(to other: Time) -> Stride { Stride(nanoseconds: other.offset - offset) }
        func advanced(by n: Stride) -> Time { Time(offset: offset + n.nanoseconds) }

        struct Interval: SchedulerTimeIntervalConvertible, SignedNumeric, Comparable, Codable, Sendable {
            var nanoseconds: Int
            init(nanoseconds: Int) { self.nanoseconds = nanoseconds }
            init(floatLiteral value: Double) { nanoseconds = Int(value * 1e9) }
            init(integerLiteral value: Int) { nanoseconds = value * 1_000_000_000 }
            init(_ value: Double) { nanoseconds = Int(value * 1e9) }
            typealias IntegerLiteralType = Int
            typealias FloatLiteralType = Double
            typealias Magnitude = Int
            var magnitude: Int { abs(nanoseconds) }
            init?<T: BinaryInteger>(exactly source: T) {
                guard let value = Int(exactly: source) else { return nil }
                nanoseconds = value
            }
            static var zero: Interval { Interval(nanoseconds: 0) }
            mutating func negate() { nanoseconds = -nanoseconds }
            static func seconds(_ s: Int) -> Interval { Interval(nanoseconds: s * 1_000_000_000) }
            static func seconds(_ s: Double) -> Interval { Interval(nanoseconds: Int(s * 1e9)) }
            static func milliseconds(_ ms: Int) -> Interval { Interval(nanoseconds: ms * 1_000_000) }
            static func microseconds(_ us: Int) -> Interval { Interval(nanoseconds: us * 1_000) }
            static func nanoseconds(_ ns: Int) -> Interval { Interval(nanoseconds: ns) }
            static func < (l: Interval, r: Interval) -> Bool { l.nanoseconds < r.nanoseconds }
            static func + (l: Interval, r: Interval) -> Interval { Interval(nanoseconds: l.nanoseconds + r.nanoseconds) }
            static func - (l: Interval, r: Interval) -> Interval { Interval(nanoseconds: l.nanoseconds - r.nanoseconds) }
            static func * (l: Interval, r: Interval) -> Interval { Interval(nanoseconds: l.nanoseconds * r.nanoseconds) }
            static func += (l: inout Interval, r: Interval) { l.nanoseconds += r.nanoseconds }
            static func -= (l: inout Interval, r: Interval) { l.nanoseconds -= r.nanoseconds }
            static func *= (l: inout Interval, r: Interval) { l.nanoseconds *= r.nanoseconds }
        }
    }

    private struct Scheduled {
        let id: Int
        let due: Time
        let action: () -> Void
    }

    private(set) var now = Time(offset: 0)
    private var queue: [Scheduled] = []
    private var nextID = 0

    /// Runs everything that becomes due within `duration`, in time order, moving `now`
    /// to each action's due time first (an action may schedule more work).
    func advance(by duration: Time.Interval) {
        let target = now.advanced(by: duration)
        while let next = queue.filter({ $0.due <= target }).min(by: { ($0.due, $0.id) < ($1.due, $1.id) }) {
            queue.removeAll { $0.id == next.id }
            now = max(now, next.due)
            next.action()
        }
        now = target
    }

    fileprivate func add(at due: Time, _ action: @escaping () -> Void) -> AnyCancellable {
        let id = nextID
        nextID += 1
        queue.append(Scheduled(id: id, due: due, action: action))
        return AnyCancellable { [weak self] in
            // Runs on whatever thread cancels; the pipeline cancels on the main actor.
            MainActor.assumeIsolated { self?.queue.removeAll { $0.id == id } }
        }
    }
}

extension ManualScheduler: @MainActor Scheduler {
    typealias SchedulerTimeType = Time
    typealias SchedulerOptions = Never

    var minimumTolerance: Time.Interval { .nanoseconds(0) }

    func schedule(options: Never?, _ action: @escaping () -> Void) { _ = add(at: now, action) }

    func schedule(after date: Time, tolerance: Time.Interval, options: Never?, _ action: @escaping () -> Void) {
        _ = add(at: date, action)
    }

    func schedule(
        after date: Time, interval: Time.Interval, tolerance: Time.Interval, options: Never?, _ action: @escaping () -> Void
    ) -> any Cancellable {
        add(at: date, action)
    }
}

// MARK: - Small synchronization helpers

final class Flag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
    /// Yields until the flag is set (no timer involved).
    func waitUntilSet() async { while !isSet { await Task.yield() } }
}

/// Suspends callers of `wait()` until `open()` is called.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Suspends until the current task is cancelled (no timer: `AsyncStream` iteration ends on cancellation).
func suspendUntilCancelled() async {
    let (stream, _) = AsyncStream.makeStream(of: Never.self)
    for await _ in stream {}
}
