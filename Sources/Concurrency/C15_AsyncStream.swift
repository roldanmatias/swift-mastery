// C15 — AsyncStream: bridging push-based APIs (delegates, callbacks,
// notifications) into `for await`.

import Synchronization

package struct AvailabilityChange: Sendable, Equatable {
    package let listingID: Int
    package let freeNights: Int
}

/// A legacy delegate-style client that pushes changes from its own thread.
package final class CalendarSyncClient: Sendable {
    private let observers = Mutex<[Int: @Sendable (AvailabilityChange) -> Void]>([:])
    private let nextToken = Atomic<Int>(0)

    package init() {}

    package func addObserver(_ observer: @escaping @Sendable (AvailabilityChange) -> Void) -> Int {
        let token = nextToken.add(1, ordering: .relaxed).newValue
        observers.withLock { $0[token] = observer }
        return token
    }

    package func removeObserver(_ token: Int) { _ = observers.withLock { $0.removeValue(forKey: token) } }
    package var observerCount: Int { observers.withLock { $0.count } }

    package func push(_ change: AvailabilityChange) {
        for observer in observers.withLock({ Array($0.values) }) { observer(change) }
    }
}

extension CalendarSyncClient {
    /// One stream per subscriber. `onTermination` runs when the consumer stops
    /// iterating, its task is cancelled or the stream is finished: that's where
    /// the observer is removed, so nothing leaks.
    package func changes(
        bufferingPolicy: AsyncStream<AvailabilityChange>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<AvailabilityChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: AvailabilityChange.self, bufferingPolicy: bufferingPolicy)
        let token = addObserver { continuation.yield($0) }
        continuation.onTermination = { [weak self] _ in self?.removeObserver(token) }
        return stream
    }
}

/// A producer that can fail: `AsyncThrowingStream` finishes with an error.
package enum SyncFailure: Error, Equatable { case connectionLost }

package func replay(_ changes: [AvailabilityChange], thenFail: Bool) -> AsyncThrowingStream<AvailabilityChange, any Error> {
    AsyncThrowingStream { continuation in
        for change in changes { continuation.yield(change) }
        continuation.finish(throwing: thenFail ? SyncFailure.connectionLost : nil)
    }
}
