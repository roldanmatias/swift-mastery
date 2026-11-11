// C20 — Bounded task groups and discarding task groups.

import Synchronization

/// Tracks how many operations are in flight, and the peak.
package final class ConcurrencyGauge: Sendable {
    private let state = Mutex((current: 0, peak: 0))
    package init() {}
    package func enter() { state.withLock { $0.current += 1; $0.peak = max($0.peak, $0.current) } }
    package func leave() { state.withLock { $0.current -= 1 } }
    package var peak: Int { state.withLock { $0.peak } }
}

package enum PhotoUploader {
    /// At most `maxConcurrent` uploads in flight; results keep the input order.
    /// Seed the group with N tasks, then add one more each time one finishes.
    package static func uploadAll(
        _ photos: [String],
        maxConcurrent: Int,
        upload: @escaping @Sendable (String) async throws -> String
    ) async throws -> [String] {
        precondition(maxConcurrent > 0)
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var results = [String?](repeating: nil, count: photos.count)
            var next = 0

            func addNext() {
                guard next < photos.count else { return }
                let index = next, photo = photos[index]       // capture values, not the counter
                group.addTask { (index, try await upload(photo)) }
                next += 1
            }

            for _ in 0..<maxConcurrent { addNext() }
            for try await (index, url) in group {
                results[index] = url
                addNext()
            }
            return results.map { $0! }
        }
    }
}

package enum WebhookProcessor {
    /// A discarding group never stores child results, so memory stays flat for
    /// an endless stream of events (a server loop). The first error cancels the
    /// whole group and is rethrown.
    package static func process(
        _ events: AsyncStream<Int>,
        handle: @escaping @Sendable (Int) async throws -> Void
    ) async throws {
        try await withThrowingDiscardingTaskGroup { group in
            for await event in events {
                group.addTask { try await handle(event) }
            }
        }
    }
}
