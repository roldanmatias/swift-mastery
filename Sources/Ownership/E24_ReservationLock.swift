// Ex 24 — Noncopyable types: `ReservationLock`.
//
// `~Copyable` removes the implicit `Copyable` conformance: a value has exactly
// one owner, ownership *moves* on assignment / pass-by-value, and the compiler
// rejects any use after the move. Structs and enums get a `deinit`.

import Synchronization

package enum LockError: Error, Hashable, Sendable {
    case alreadyHeld(listingID: Int)
}

package struct ReleaseReceipt: Hashable, Sendable {
    package let listingID: Int
    package let token: UInt64
    /// `true` when the lock was released by `deinit` (dropped) instead of `release()`.
    package let wasForced: Bool
}

/// Thread-safe registry of held locks. `Mutex` (Synchronization module, macOS 15+)
/// is itself `~Copyable`, so it must live in a class or a global/static `let`.
package final class LockRegistry: Sendable {
    package static let shared = LockRegistry()

    struct State {
        var nextToken: UInt64 = 1
        var held: [Int: UInt64] = [:]
        var receipts: [ReleaseReceipt] = []
    }

    private let state = Mutex(State())

    func acquire(_ listingID: Int) throws(LockError) -> UInt64 {
        try state.withLock { (state: inout State) throws(LockError) -> UInt64 in
            guard state.held[listingID] == nil else { throw .alreadyHeld(listingID: listingID) }
            let token = state.nextToken
            state.nextToken += 1
            state.held[listingID] = token
            return token
        }
    }

    func release(_ listingID: Int, token: UInt64, forced: Bool) -> ReleaseReceipt {
        state.withLock { state in
            let receipt = ReleaseReceipt(listingID: listingID, token: token, wasForced: forced)
            if state.held[listingID] == token { state.held[listingID] = nil }
            state.receipts.append(receipt)
            return receipt
        }
    }

    func rotate(_ listingID: Int, from token: UInt64) -> UInt64 {
        state.withLock { state in
            precondition(state.held[listingID] == token, "rotating a lock that isn't held")
            let next = state.nextToken
            state.nextToken += 1
            state.held[listingID] = next
            return next
        }
    }

    package func isHeld(_ listingID: Int) -> Bool {
        state.withLock { $0.held[listingID] != nil }
    }

    package var heldCount: Int {
        state.withLock { $0.held.count }
    }

    package func receipts(for listingID: Int) -> [ReleaseReceipt] {
        state.withLock { $0.receipts.filter { $0.listingID == listingID } }
    }
}

/// Stores only trivially-destroyed fields (`Int`, `UInt64`): that's a
/// requirement of `discard self` (see the note at the bottom), which is why the
/// lock talks to the process-wide `LockRegistry.shared` instead of storing a
/// registry reference.
package struct ReservationLock: ~Copyable {
    package let listingID: Int
    package private(set) var token: UInt64

    private var registry: LockRegistry { .shared }

    package init(acquiring listingID: Int) throws(LockError) {
        // If this throws, `self` was never fully initialized, so `deinit` won't run.
        self.token = try LockRegistry.shared.acquire(listingID)
        self.listingID = listingID
    }

    /// Explicit release. `consuming`: the caller's lock is gone afterwards.
    /// `discard self` ends the lifetime WITHOUT running `deinit`, so the
    /// lock is released exactly once.
    package consuming func release() -> ReleaseReceipt {
        let receipt = registry.release(listingID, token: token, forced: false)
        discard self
        return receipt
    }

    /// Ex 25 — mutated through `inout`: a new token for the same listing.
    package mutating func rotateToken() {
        token = registry.rotate(listingID, from: token)
    }

    /// Safety net: a dropped lock is still released (deterministically, at the
    /// end of the owner's scope; no refcount, no "some other reference" left).
    deinit {
        _ = registry.release(listingID, token: token, forced: true)
    }
}

// Step 3 — compile errors (recorded with Swift 6.4.2):
//
//   let lock = try ReservationLock(acquiring: 1)
//   let other = lock
//   _ = lock.release()
//   // error: 'lock' consumed more than once     (the `let other = lock` was the first consume)
//
//   _ = lock.release(); _ = lock.release()
//   // error: 'lock' consumed more than once
//
//   let locks: [ReservationLock] = []
//   // error: type 'ReservationLock' does not conform to protocol 'Copyable'
//   //        (Array requires Copyable elements → Ex 30 uses UniqueArray)
//
//   let task = { _ = lock.release() }   // escaping closure
//   // error: noncopyable 'lock' cannot be consumed when captured by an escaping closure
//   //        or borrowed by a non-Escapable type
//
// Step 2 — `discard self` restriction (still present in Swift 6.4.2). Adding a
// stored `let registry: LockRegistry` (a class reference, not trivially
// destroyed) makes the full compile fail:
//
//   error: can only 'discard' type 'ReservationLock' if it contains
//          trivially-destroyed stored properties at this time
//
// Note: `swiftc -typecheck` does NOT report it; it's a SIL-level diagnostic,
// so you only see it on a real build.
