// C08 — Generic async helpers that don't fight the caller's isolation.
//
// A plain `nonisolated func helper(_ op: () async -> T) async` runs on the
// global executor (Swift 6 defaults), so `op` and `T` cross a boundary and the
// caller's non-Sendable closures are rejected. Two fixes:
//   • 6.0: an `isolated (any Actor)? = #isolation` parameter (SE-0420)
//   • 6.2: `nonisolated(nonsending)` (SE-0461): "run on whatever actor called me"

package enum RetryError: Error, Equatable {
    case exhausted(attempts: Int)
}

/// Swift 6.0 style. The function runs on the caller's actor, so `operation`
/// doesn't need to be `@Sendable` and `T` doesn't need to be `Sendable`.
package func withRetry<T>(
    attempts: Int,
    isolation: isolated (any Actor)? = #isolation,
    _ operation: () async throws -> T
) async throws -> T {
    for _ in 0..<attempts {
        if let value = try? await operation() { return value }
    }
    throw RetryError.exhausted(attempts: attempts)
}

/// Swift 6.2 style: same semantics, no extra parameter in the signature.
nonisolated(nonsending)
package func withRetryNonsending<T>(
    attempts: Int,
    _ operation: nonisolated(nonsending) () async throws -> T
) async throws -> T {
    for _ in 0..<attempts {
        if let value = try? await operation() { return value }
    }
    throw RetryError.exhausted(attempts: attempts)
}

/// Reports the isolation it *runs on*, which is the caller's.
nonisolated(nonsending)
package func nonsendingLabel() async -> String { isolationLabel() }

/// A plain nonisolated async function under Swift 6 defaults: always hops off.
package func plainNonisolatedLabel() async -> String { isolationLabel() }

// MARK: - @isolated(any): closures that carry their isolation (SE-0431)

/// A scheduler that stores jobs *and* knows where each one wants to run,
/// without forcing them all onto one actor. `Task.init` takes the same kind of
/// closure, so the runtime can enqueue directly on the right executor.
package final class JobQueue: Sendable {
    package typealias Job = @isolated(any) @Sendable () async -> Void

    package init() {}

    /// The isolation is available *synchronously* through `job.isolation`.
    package func isolationName(of job: Job) -> String {
        guard let actor = job.isolation else { return "nonisolated" }
        if actor === MainActor.shared { return "MainActor" }
        return String(describing: type(of: actor))
    }

    package func run(_ job: Job) async {
        await job()   // calling an @isolated(any) function is always an `await`
    }
}
