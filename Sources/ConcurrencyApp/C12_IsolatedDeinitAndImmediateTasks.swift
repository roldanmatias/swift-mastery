// C12 — Two Swift 6.2 lifecycle tools: `isolated deinit` (SE-0371) and
// `Task.immediate` (SE-0472).

/// Main-actor registry of active upload sessions (implicitly @MainActor).
package final class UploadRegistry {
    package static let shared = UploadRegistry()
    package private(set) var active: Set<Int> = []
    package func register(_ id: Int) { active.insert(id) }
    package func unregister(_ id: Int) { active.remove(id) }
}

package final class PhotoUploadSession {
    package let id: Int

    package init(id: Int) {
        self.id = id
        UploadRegistry.shared.register(id)
    }

    /// A plain `deinit` is always nonisolated, so it couldn't touch the
    /// main-actor registry. `isolated deinit` runs on the main actor: inline if
    /// the last release happens there, otherwise enqueued onto it.
    isolated deinit {
        UploadRegistry.shared.unregister(id)
    }
}

/// `Task.immediate` starts running *synchronously* on the caller's actor until
/// its first real suspension. `Task {}` is only enqueued, so it starts later.
package final class EventLog {
    package private(set) var events: [String] = []
    package init() {}
    package func append(_ event: String) { events.append(event) }

    package func startImmediate() -> Task<Void, Never> {
        Task.immediate {
            self.append("immediate: started")
            await Task.yield()
            self.append("immediate: resumed")
        }
    }

    package func startEnqueued() -> Task<Void, Never> {
        Task {
            self.append("enqueued: started")
        }
    }
}
