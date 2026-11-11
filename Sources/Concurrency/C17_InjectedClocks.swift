// C17 — Deterministic time: inject a `Clock` instead of calling `Task.sleep`.
//
// Retry-with-backoff and timeouts are time-based, so tests that use real time are
// slow and flaky. Production passes `ContinuousClock()`, tests pass `ManualClock`
// and move time forward explicitly. No test ever sleeps.

import Synchronization

/// A clock whose time only moves when `advance(by:)` is called.
package final class ManualClock: Clock, Sendable {
    package struct Instant: InstantProtocol {
        package var offset: Duration
        package func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        package func duration(to other: Instant) -> Duration { other.offset - offset }
        package static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var cancelled: Set<Int> = []
        var nextID = 0
        var sleeperWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        /// Removes and returns the `waitForSleepers` callers that are now satisfied.
        mutating func takeSatisfiedWaiters() -> [CheckedContinuation<Void, Never>] {
            let count = sleepers.count
            let ready = sleeperWaiters.filter { $0.count <= count }.map(\.continuation)
            sleeperWaiters.removeAll { $0.count <= count }
            return ready
        }
    }

    private let state = Mutex(State())

    package init() {}

    package var now: Instant { state.withLock { $0.now } }
    package var minimumResolution: Duration { .zero }

    package func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = state.withLock { state in defer { state.nextID += 1 }; return state.nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Outcome { case resume, cancel, wait([CheckedContinuation<Void, Never>]) }
                let outcome: Outcome = state.withLock { state in
                    if state.cancelled.remove(id) != nil { return .cancel }   // cancelled before registering
                    if deadline <= state.now { return .resume }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .wait(state.takeSatisfiedWaiters())
                }
                switch outcome {
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                case .wait(let waiters): waiters.forEach { $0.resume() }
                }
            }
        } onCancel: {
            let sleeper: Sleeper? = state.withLock { state in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    state.cancelled.insert(id)
                    return nil
                }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline has passed.
    package func advance(by duration: Duration) {
        let due: [Sleeper] = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        due.sorted { $0.deadline < $1.deadline }.forEach { $0.continuation.resume() }
    }

    /// Suspends until at least `count` tasks are sleeping on this clock. Tests call
    /// it before `advance` so they never race the code under test.
    package func waitForSleepers(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { state in
                if state.sleepers.count >= count { return true }
                state.sleeperWaiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

// MARK: - Code under test: generic over the clock

package struct Backoff: Sendable {
    package var initialDelay: Duration
    package var multiplier: Int
    package var maxAttempts: Int
    package init(initialDelay: Duration, multiplier: Int = 2, maxAttempts: Int) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxAttempts = maxAttempts
    }

    /// Delay before retry number `retry` (1-based): 100ms, 200ms, 400ms…
    package func delay(beforeRetry retry: Int) -> Duration {
        var delay = initialDelay
        for _ in 1..<retry { delay *= multiplier }
        return delay
    }
}

package func retrying<T: Sendable>(
    _ backoff: Backoff,
    clock: some Clock<Duration>,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var attempt = 1
    while true {
        do {
            return try await operation()
        } catch {
            guard attempt < backoff.maxAttempts else { throw error }
            try await clock.sleep(for: backoff.delay(beforeRetry: attempt))   // cancellable
            attempt += 1
        }
    }
}

package struct TimeoutError: Error, Equatable {}

/// Races the operation against the clock; the loser is cancelled.
package func withTimeout<T: Sendable>(
    _ timeout: Duration,
    clock: some Clock<Duration>,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await clock.sleep(for: timeout)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
