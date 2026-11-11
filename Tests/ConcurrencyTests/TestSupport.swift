// Deterministic synchronization helpers for the concurrency tests.
// Rule: no test sleeps. Tests coordinate with gates, barriers, streams and
// `ManualClock`, so they pass the same way on a loaded CI machine.

import Synchronization

/// A thread-safe counter that can be captured by `@Sendable` closures.
final class Counter: Sendable {
    private let value = Mutex(0)
    @discardableResult func increment() -> Int { value.withLock { $0 += 1; return $0 } }
    var current: Int { value.withLock { $0 } }
}

/// A thread-safe write-once-or-more flag.
final class Flag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
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

/// Suspends each arriving task until `count` tasks have arrived.
actor AsyncBarrier {
    private let count: Int
    private var arrived = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) { self.count = count }

    func arrive() async {
        arrived += 1
        if arrived >= count {
            waiters.forEach { $0.resume() }
            waiters.removeAll()
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Suspends until the current task is cancelled. No timer involved:
/// `AsyncStream` iteration returns `nil` on cancellation.
func suspendUntilCancelled() async {
    let (stream, continuation) = AsyncStream.makeStream(of: Never.self)
    _ = continuation      // keep the stream open
    for await _ in stream {}
}

/// Yields until `condition` holds (bounded, so a bug fails the test instead of hanging).
func eventually(_ condition: @Sendable () async -> Bool, maxYields: Int = 10_000) async -> Bool {
    for _ in 0..<maxYields {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

/// Tests run in parallel and some share global registries: every test takes fresh IDs.
enum TestIDs {
    private static let counter = Atomic<Int>(1_000)
    static func next() -> Int { counter.add(1, ordering: .relaxed).newValue }
}
