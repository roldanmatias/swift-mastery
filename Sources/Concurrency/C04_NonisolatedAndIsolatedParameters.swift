// C04 — `nonisolated` members and `isolated` parameters.
//
// `nonisolated` opts one member out of the actor (it can't touch mutable state,
// but it can be called synchronously from anywhere). An `isolated` parameter
// does the opposite: it moves a whole function *into* an actor's domain, so many
// operations cost one hop instead of one `await` each.

package struct InboxMessage: Sendable, Equatable {
    package let from: String
    package let text: String
    package var isRead = false
    package init(from: String, text: String) { self.from = from; self.text = text }
}

package actor HostInbox: Hashable, CustomStringConvertible {
    /// A `let` of a Sendable type is implicitly nonisolated, but **only inside
    /// this module**. Other modules (the tests too) would need `await`, unless
    /// it's spelled `nonisolated let`, which makes it part of the API contract.
    package nonisolated let hostID: Int
    private var messages: [InboxMessage] = []

    package init(hostID: Int) { self.hostID = hostID }

    // Protocol requirements that are synchronous must be satisfied by
    // nonisolated members: they only use the immutable `hostID`.
    package nonisolated var description: String { "HostInbox(\(hostID))" }
    package static func == (lhs: HostInbox, rhs: HostInbox) -> Bool { lhs.hostID == rhs.hostID }
    package nonisolated func hash(into hasher: inout Hasher) { hasher.combine(hostID) }

    package func receive(_ message: InboxMessage) { messages.append(message) }
    package var unreadCount: Int { messages.count(where: { !$0.isRead }) }
    package var count: Int { messages.count }

    package func markAllRead() {
        for index in messages.indices { messages[index].isRead = true }
    }

    package func archive(keepingLast n: Int) {
        messages = Array(messages.suffix(n))
    }

    /// A transaction: `body` runs on the actor with synchronous access to it, so
    /// no other call can interleave between its steps (no suspension inside).
    package func transaction<T: Sendable>(_ body: @Sendable (isolated HostInbox) throws -> T) rethrows -> T {
        try body(self)
    }
}

/// A free function isolated to its `inbox` argument: three synchronous calls,
/// one hop for the caller (`await triage(inbox, …)`), and no interleaving.
package func triage(_ inbox: isolated HostInbox, keepingLast n: Int) -> Int {
    inbox.markAllRead()
    inbox.archive(keepingLast: n)
    return inbox.count
}
