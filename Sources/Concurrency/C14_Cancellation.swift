// C14 — Cancellation is cooperative: nothing stops unless the code checks.

import Synchronization

package struct ImportReport: Sendable, Equatable {
    package let imported: Int
    package let wasCancelled: Bool
}

package enum ListingImporter {
    /// Checks for cancellation between units of work and returns a *partial*
    /// report instead of throwing, because the work already done is valid.
    package static func importPages(
        _ pages: AsyncStream<[Int]>,
        store: @Sendable ([Int]) async -> Void
    ) async -> ImportReport {
        var imported = 0
        for await page in pages {
            if Task.isCancelled { return ImportReport(imported: imported, wasCancelled: true) }
            await store(page)
            imported += page.count
        }
        return ImportReport(imported: imported, wasCancelled: Task.isCancelled)
    }
}

/// A pre-concurrency download API with its own cancel token.
package final class LegacyDownload: Sendable {
    private let state = Mutex<(handler: (@Sendable (Result<[UInt8], any Error>) -> Void)?, cancelled: Bool)>((nil, false))

    package init() {}

    /// If `cancel()` already happened, fail immediately: otherwise a cancellation
    /// that arrives *before* `start` would be lost and the caller would hang.
    package func start(_ handler: @escaping @Sendable (Result<[UInt8], any Error>) -> Void) {
        let alreadyCancelled = state.withLock { state in
            if !state.cancelled { state.handler = handler }
            return state.cancelled
        }
        if alreadyCancelled { handler(.failure(CancellationError())) }
    }

    package var hasPendingHandler: Bool { state.withLock { $0.handler != nil } }

    /// Simulates the network finishing.
    package func complete(with bytes: [UInt8]) {
        let handler = state.withLock { state in defer { state.handler = nil }; return state.handler }
        handler?(.success(bytes))
    }

    package func cancel() {
        let handler = state.withLock { state in
            state.cancelled = true
            defer { state.handler = nil }
            return state.handler
        }
        handler?(.failure(CancellationError()))
    }

    package var wasCancelled: Bool { state.withLock { $0.cancelled } }
}

extension LegacyDownload {
    /// Bridges both the result *and* cancellation. The handler runs immediately
    /// if the task is already cancelled, and concurrently with `operation` otherwise,
    /// so it must be `@Sendable` and only touch thread-safe state.
    package func bytes() async throws -> [UInt8] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start { continuation.resume(with: $0) }
            }
        } onCancel: {
            cancel()
        }
    }
}

/// What a child inherits from its parent, by kind of task.
package enum Inheritance {
    package struct Observed: Sendable, Equatable {
        package let asyncLetCancelled: Bool
        package let unstructuredCancelled: Bool
        package let detachedCancelled: Bool
    }

    /// Cancels the current task, then reports what each kind of child sees.
    package static func observeAfterCancelling() async -> Observed {
        withUnsafeCurrentTask { $0?.cancel() }

        async let child = Task.isCancelled                                  // structured: inherits
        let unstructured = await Task { Task.isCancelled }.value           // unstructured: doesn't
        let detached = await Task.detached { Task.isCancelled }.value      // detached: doesn't
        return Observed(asyncLetCancelled: await child, unstructuredCancelled: unstructured, detachedCancelled: detached)
    }
}
