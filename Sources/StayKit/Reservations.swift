// StayKit — C10: typestate reservations (Ex 24–27).
//
//   DraftReservation ──confirm──▶ ConfirmedReservation ──cancel──▶ CancelledReservation
//        (holds the lock)              (lock moved in)                 (lock released)
//
// Every arrow consumes the previous state, so "confirm twice" or "cancel a
// draft" are compile errors, not runtime checks.

import Foundation
import Language
import Ownership

/// Holding the `ReservationLock` *inside* the draft means a dropped draft
/// releases its hold automatically (the lock's `deinit`).
struct DraftReservation: ~Copyable {
    let quote: Quote
    let lock: ReservationLock

    var listingID: ListingID { quote.listingID }
}

struct ConfirmedReservation: ~Copyable {
    let id: ReservationID
    let receipt: Receipt
    let quote: Quote
    let lock: ReservationLock

    var listingID: ListingID { quote.listingID }
    var nights: Range<Int> { quote.nights }
}

/// Terminal state: nothing left to enforce, so it's an ordinary value.
struct CancelledReservation: Hashable, Sendable {
    let id: ReservationID
    let listingID: ListingID
    let reason: String
    let lockReleasedNormally: Bool
}

#if compiler(>=6.4)
/// Group bookings (a team trip): several listings held atomically. The locks
/// live in a `LockPool` (backed by `UniqueArray<ReservationLock>`, Ex 30). If
/// any acquisition fails, the partially-built pool is dropped, which releases
/// every lock it already holds.
@available(macOS 27, iOS 27, *)
struct GroupHold: ~Copyable {
    let quotes: [Quote]
    var pool: LockPool

    var count: Int { pool.count }

    consuming func release() -> [ReleaseReceipt] {
        pool.releaseAll()
    }
}
#endif
