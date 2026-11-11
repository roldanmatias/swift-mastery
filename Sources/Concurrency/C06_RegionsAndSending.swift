// C06 — Region-based isolation (SE-0414) and `sending` (SE-0430).
//
// A non-Sendable value may still cross an isolation boundary if the compiler
// can prove it's *disconnected*: nothing else can reach it afterwards. `sending`
// writes that requirement into a signature.

/// Deliberately non-Sendable: a mutable class with no synchronization.
package final class ReservationDraft {
    package var listingID: Int
    package var nights: ClosedRange<Int>
    package var notes: [String] = []

    package init(listingID: Int, nights: ClosedRange<Int>) {
        self.listingID = listingID
        self.nights = nights
    }

    package init(copying other: ReservationDraft) {
        listingID = other.listingID
        nights = other.nights
        notes = other.notes
    }
}

package actor ReservationOutbox {
    private var pending: [ReservationDraft] = []

    package init() {}

    /// Region isolation lets a caller pass a fresh draft here without `sending`
    /// in the signature: an actor-isolated parameter is merged into the actor's region.
    package func submit(_ draft: ReservationDraft) { pending.append(draft) }

    package var count: Int { pending.count }
    package var listingIDs: [Int] { pending.map(\.listingID) }

    /// The actor can't hand out a draft it still stores (that would share it).
    /// It must return a *new* object built only from Sendable values: then the
    /// result is disconnected and `sending` is satisfied.
    ///
    /// ⚙️ `ReservationDraft(copying: first)` is rejected ("task or actor-isolated
    /// value cannot be sent"): an initializer that takes a non-Sendable argument
    /// might store it, so the compiler merges the result into `first`'s region.
    package func exportFirst() -> sending ReservationDraft? {
        guard let first = pending.first else { return nil }
        let (listingID, nights, notes) = (first.listingID, first.nights, first.notes)
        let copy = ReservationDraft(listingID: listingID, nights: nights)
        copy.notes = notes
        return copy
    }
}

/// `sending` result: every call returns a value no one else references, so the
/// caller can send it anywhere (even from a non-Sendable type).
package func makeDraft(listingID: Int, nights: ClosedRange<Int>, note: String) -> sending ReservationDraft {
    let draft = ReservationDraft(listingID: listingID, nights: nights)
    draft.notes.append(note)
    return draft
}

/// A `sending` parameter is disconnected on entry, so it can be handed to an actor.
/// Without `sending`, `draft` would be in the caller's region and the call is an error.
package func forward(_ draft: sending ReservationDraft, to outbox: ReservationOutbox) async {
    await outbox.submit(draft)
}

/// `Task.init` takes a `sending` closure. Capturing a `sending` parameter is
/// allowed (the caller gave it up), and the task may use it freely.
///
/// ⚙️ But the task can't send it *again* (`Task { await outbox.submit(draft) }`
/// fails): captured values belong to the closure's region, because a closure
/// could run more than once. Hand values to actors directly (`forward`) instead.
package func annotateInBackground(_ draft: sending ReservationDraft, note: String) -> Task<Int, Never> {
    Task {
        draft.notes.append(note)
        return draft.notes.count
    }
}
