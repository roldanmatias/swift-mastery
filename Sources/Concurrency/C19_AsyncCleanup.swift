// C19 — Async cleanup that survives cancellation.
//
// Swift 6.4 adds two tools, verified on 6.4.2:
//   • `await` inside `defer` (SE-0493): async cleanup on every exit path.
//     ⚙️ It runs *in the same task*, so if the task was cancelled the cleanup
//     sees `Task.isCancelled == true` and cancellable awaits inside it
//     (network calls, `Task.sleep`) bail out early.
//   • `withTaskCancellationShield` (SE-0504) hides cancellation from a scope.
//     ⚙️ It's `@available(anyAppleOS 27.0, *)`, and on macOS 26 a binary that
//     merely *contains* the call fails to launch, even behind `#available`:
//     dyld: "Symbol not found: _swift_task_cancellationShieldPop". The runtime
//     entry point isn't weak-linked. So it's compiled only with
//     `-DHAS_TASK_CANCELLATION_SHIELD` (for macOS/iOS 27 deployment targets).
// The portable shield until then: an unstructured task, which doesn't inherit cancellation.

/// The pre-6.4/pre-27 cancellation shield: an *unstructured* task doesn't inherit
/// cancellation, so awaiting its value runs `work` un-cancelled. (It does inherit
/// priority, task-locals and actor isolation.)
package func shielded(_ work: @escaping @Sendable () async -> Void) async {
    await Task { await work() }.value
}

/// Runs `operation`, then always runs `cleanup` (on success, on error and on
/// cancellation) and lets `cleanup` finish its async work even if the task was
/// cancelled. Works on Swift 6.0+.
package func withAsyncCleanup<T: Sendable>(
    _ operation: @Sendable () async throws -> T,
    cleanup: @escaping @Sendable () async -> Void
) async throws -> T {
    let result: Result<T, any Error>
    do { result = .success(try await operation()) } catch { result = .failure(error) }
    await shielded(cleanup)
    return try result.get()
}

#if compiler(>=6.4)
/// Swift 6.4 `defer { await … }`: the cleanup runs on every exit path, in this task.
package func syncReleasingInDefer(_ lease: SyncLease, work: @Sendable () async throws -> Void) async throws {
    defer { await lease.release() }
    try await work()
}

/// Both together: `defer` guarantees the cleanup runs, the shield lets it finish.
package func syncReleasingInShieldedDefer(_ lease: SyncLease, work: @Sendable () async throws -> Void) async throws {
    defer { await shielded { await lease.release() } }
    try await work()
}
#endif

#if HAS_TASK_CANCELLATION_SHIELD   // swift build -Xswiftc -DHAS_TASK_CANCELLATION_SHIELD (macOS/iOS 27 only)
@available(macOS 27.0, iOS 27.0, *)
package func syncReleasingWithShield(_ lease: SyncLease, work: () async throws -> Void) async throws {
    defer { await withTaskCancellationShield { await lease.release() } }   // no extra task, no hop
    try await work()
}
#endif

/// A sync session with a lease that must be released on the server.
package actor SyncLease {
    package private(set) var released = false
    package private(set) var releaseSawCancellation: Bool?
    package init() {}

    package func release() {
        releaseSawCancellation = Task.isCancelled
        released = true
    }
}
