// C02 — Global actors: one shared isolation domain for many types and functions.
//
// `@MainActor` is the global actor everybody knows. Declare your own when a
// subsystem (sync, database, analytics) needs a single serial domain that spans
// several types, without making each of them an actor.

import Dispatch

@globalActor
package actor SyncActor {
    package static let shared = SyncActor()
}

/// Every member runs on `SyncActor`. A global-actor-isolated class is
/// implicitly `Sendable`: the actor protects all its state.
@SyncActor
package final class SyncJournal {
    package private(set) var entries: [String] = []
    package init() {}
    package func append(_ entry: String) { entries.append(entry) }
}

/// Another type in the *same* domain: calls between them are synchronous.
@SyncActor
package final class SyncSession {
    private let journal: SyncJournal
    package init(journal: SyncJournal) { self.journal = journal }

    package func run(listingIDs: [Int]) -> Int {
        for id in listingIDs { journal.append("synced \(id)") }   // no await: same domain
        return journal.entries.count
    }
}

/// A single global-actor-isolated function.
@SyncActor package func syncDomainLabel() -> String { isolationLabel() }

// MARK: - Legacy code that is *known* to call back on the main thread

/// Pre-concurrency API: documents "the handler is always called on the main queue",
/// but the compiler can't know that.
package final class LegacyMainQueueNotifier: Sendable {
    package init() {}
    package func notify(_ handler: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: handler)
    }
}

@MainActor
package final class BadgeModel {
    package private(set) var unread = 0
    package init() {}
    package func increment() { unread += 1 }
}

extension BadgeModel {
    /// `MainActor.assumeIsolated` checks at runtime (and traps if wrong) instead
    /// of hopping. Use it only when the thread is guaranteed by the API contract.
    package nonisolated func subscribe(to notifier: LegacyMainQueueNotifier, done: @escaping @Sendable () -> Void) {
        notifier.notify {
            MainActor.assumeIsolated { self.increment() }
            done()
        }
    }
}
