// C10 — `nonisolated(nonsending)` vs `@concurrent` (SE-0461, Swift 6.2).
//
// Swift 6.0/6.1: a `nonisolated async` function always ran on the global
// executor. Swift 6.2 with `NonisolatedNonsendingByDefault` (on in this target):
// it runs on the *caller's* actor, like a synchronous function would. To leave
// the caller's actor you now say so: `@concurrent`.

import Foundation

nonisolated package enum ExecutionProbe {
    /// `nonisolated(nonsending)` by default in this target: inherits the caller.
    package static func inheritsCaller() async -> Bool {
        isOnMainActor()
    }

    /// Spelled out (the same as the default here, but clear to readers and
    /// stable if the setting changes).
    nonisolated(nonsending) package static func explicitlyNonsending() async -> Bool {
        isOnMainActor()
    }

    /// Always runs on the global concurrent executor, whoever calls it.
    @concurrent package static func alwaysOffActor() async -> Bool {
        isOnMainActor()
    }

    /// Thread-level check as a second opinion (the main actor runs on the main thread).
    @concurrent package static func concurrentRunsOnMainThread() async -> Bool {
        pthread_main_np() != 0
    }

    package static func nonsendingRunsOnMainThread() async -> Bool {
        pthread_main_np() != 0
    }
}
