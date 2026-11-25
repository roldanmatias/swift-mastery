// Combine exercise — the three operators Combine gives you for free and
// `AsyncSequence` does not: `debounce`, `removeDuplicates` and `switchToLatest`
// (here `mapLatest`). Hand-written so every line of the semantics is visible.
//
// Shape: each operator is a function returning an `AsyncStream`. A child task
// pumps the upstream sequence; `onTermination` cancels that task, so dropping the
// stream (or cancelling its consumer) tears the whole chain down.

import Synchronization

private struct Latest {
    var generation = 0
    var task: Task<Void, Never>?
}

/// A class around the `Mutex`: Swift 6.3 rejects capturing a noncopyable `let` in a `Task` closure.
private final class LatestBox: Sendable {
    private let mutex = Mutex(Latest())
    func withLock<R: Sendable>(_ body: (inout Latest) -> R) -> R { mutex.withLock { body(&$0) } }
}

extension AsyncSequence where Self: Sendable, Element: Sendable, Failure == Never {

    /// Emits an element only after `duration` of silence. Each new element restarts
    /// the timer and drops the one waiting. Time comes from an injected `clock`.
    ///
    /// At upstream end, the element still waiting is flushed, then the stream finishes.
    package func debounced<C: Clock>(
        for duration: C.Duration,
        clock: C
    ) -> AsyncStream<Element> where C: Sendable {
        let (stream, output) = AsyncStream.makeStream(of: Element.self)
        let pending = Mutex<Task<Void, Never>?>(nil)

        let pump = Task {
            for await element in self {
                // Cancel the old timer *before* creating the new one, inside one critical
                // section, so at most one timer is ever alive.
                pending.withLock { slot in
                    slot?.cancel()
                    slot = Task {
                        guard (try? await clock.sleep(for: duration)) != nil else { return }
                        output.yield(element)
                    }
                }
            }
            await pending.withLock { $0 }?.value
            output.finish()
        }
        output.onTermination = { _ in
            pump.cancel()
            pending.withLock { $0?.cancel() }
        }
        return stream
    }

    /// Drops an element equal to the previous one.
    package func removingDuplicates() -> AsyncStream<Element> where Element: Equatable {
        let (stream, output) = AsyncStream.makeStream(of: Element.self)
        let pump = Task {
            var last: Element?
            for await element in self {
                if element != last { output.yield(element) }
                last = element
            }
            output.finish()
        }
        output.onTermination = { _ in pump.cancel() }
        return stream
    }

    /// Runs `transform` for each element; a newer element cancels the run in flight and
    /// its result is never emitted. This is Combine's `map { publisher }.switchToLatest()`.
    package func mapLatest<T: Sendable>(
        _ transform: @escaping @Sendable (Element) async -> T
    ) -> AsyncStream<T> {
        let (stream, output) = AsyncStream.makeStream(of: T.self)
        let latest = LatestBox()

        let pump = Task {
            for await element in self {
                // Step 1 (one critical section): cancel the old run and take a new generation number.
                let mine = latest.withLock { state -> Int in
                    state.task?.cancel()
                    state.generation += 1
                    return state.generation
                }
                // Step 2: start the run. The loop is sequential, so nobody else can bump the
                // generation between the two steps. (Creating the `Task` inside `withLock` is
                // rejected by the Swift 6.3 compiler.)
                let run = Task {
                    let value = await transform(element)
                    // A cancelled task can still return a value (the service may ignore
                    // cancellation). Check "am I still the latest?" and yield in one
                    // critical section, so a stale result can never slip out.
                    latest.withLock { state in
                        if state.generation == mine { output.yield(value) }
                    }
                }
                latest.withLock { $0.task = run }
                // Teardown cancels the pump *first*, then the stored run. If it happened between
                // step 1 and here, the run was not stored yet, so cancel it ourselves.
                if Task.isCancelled { run.cancel() }
            }
            await latest.withLock { $0.task }?.value
            output.finish()
        }
        output.onTermination = { _ in
            pump.cancel()
            latest.withLock { $0.task?.cancel() }
        }
        return stream
    }
}
