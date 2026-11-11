// C18 — Task-local values and priority: context that travels with a task.

import Synchronization

package enum RequestContext {
    /// Bound with `$requestID.withValue(_:operation:)` for a scope, read anywhere
    /// below it with no parameter threading (tracing, logging, feature flags).
    @TaskLocal package static var requestID: String?
}

package func logLine(_ message: String) -> String {
    "[\(RequestContext.requestID ?? "-")] \(message)"
}

package struct TaskLocalPropagation: Sendable, Equatable {
    package let asyncLet: String?
    package let groupChild: String?
    package let unstructured: String?
    package let detached: String?
}

/// Structured children and `Task {}` copy task-locals; `Task.detached` starts empty.
package func observeTaskLocalPropagation() async -> TaskLocalPropagation {
    await RequestContext.$requestID.withValue("req-42") {
        async let fromAsyncLet = RequestContext.requestID
        let fromGroup = await withTaskGroup(of: String?.self) { group in
            group.addTask { RequestContext.requestID }
            return await group.next() ?? nil
        }
        let fromTask = await Task { RequestContext.requestID }.value
        let fromDetached = await Task.detached { RequestContext.requestID }.value
        return TaskLocalPropagation(
            asyncLet: await fromAsyncLet, groupChild: fromGroup,
            unstructured: fromTask, detached: fromDetached
        )
    }
}

// MARK: - Priority escalation (SE-0462, Swift 6.2)

/// A background prefetch that the UI can escalate when the user actually opens
/// the listing. The handler sees the escalation and could, for example, bump
/// the priority of an underlying network request.
package final class Prefetch: Sendable {
    private struct State {
        var escalations: [TaskPriority] = []
        var gate: CheckedContinuation<Void, Never>?
        var startedWaiter: CheckedContinuation<Void, Never>?
    }
    /// One lock for all of it: two separate locks would let `waitUntilStarted`
    /// miss the wake-up (check gate → task sets gate and reads no waiter → waiter registers).
    private let state = Mutex(State())

    package init() {}

    package var observedEscalations: [TaskPriority] { state.withLock { $0.escalations } }

    /// Starts a low-priority task that waits for `finish()`.
    package func start() -> Task<TaskPriority, Never> {
        Task(priority: .low) {
            await withTaskPriorityEscalationHandler {
                await withCheckedContinuation { continuation in
                    let waiter = state.withLock { state in
                        state.gate = continuation
                        defer { state.startedWaiter = nil }
                        return state.startedWaiter
                    }
                    waiter?.resume()
                }
                return Task.currentPriority
            } onPriorityEscalated: { _, new in
                self.state.withLock { $0.escalations.append(new) }
            }
        }
    }

    package func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let started = state.withLock { state in
                if state.gate != nil { return true }
                state.startedWaiter = continuation
                return false
            }
            if started { continuation.resume() }
        }
    }

    package func finish() {
        let gate = state.withLock { state in defer { state.gate = nil }; return state.gate }
        gate?.resume()
    }
}
