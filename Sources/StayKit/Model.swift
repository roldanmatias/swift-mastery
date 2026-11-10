// StayKit — capstone. Model types.
//
// Rule of the codebase: value types at the edges; unique ownership (`~Copyable`)
// for anything that must happen exactly once (a lock, a payment, a confirmation).

import Foundation
import Language

enum ReservationTag {}
/// C1 — phantom-typed IDs: a `ReservationID` can't be passed as a `ListingID`.
typealias ReservationID = Tagged<ReservationTag, UUID>

/// Why a struct: a quote is a snapshot value. Copying it is free and safe, and
/// a caller can keep it to retry `hold(_:)` after a failed payment.
struct Quote: Hashable, Sendable {
    let listingID: ListingID
    let nights: Range<Int>        // day indices in the listing's calendar
    let guests: Int
    let total: Decimal
    /// Computed through the `InlineArray` + `Span` hot path (display/ranking only).
    let averageNightly: Double
}

/// C11 — a payment token is single-use: `~Copyable` + `consuming` means the
/// compiler rejects charging the same token twice.
struct PaymentToken: ~Copyable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    /// Ends the token's lifetime and hands its value to the payment gateway.
    consuming func redeem() -> String { value }

    borrowing func isLikelyValid() -> Bool { !value.isEmpty }
}

#if compiler(>=6.4)
/// Swift 6.4 (SE-0499): noncopyable types can be `Equatable`/`Hashable`
/// (synthesized here). Comparing tokens borrows both sides: nothing is copied.
extension PaymentToken: Hashable {}
#endif

/// C14 — Swift 6.4 (SE-0502): `private` properties with a default value are
/// excluded from the memberwise initializer, so the synthesized init is
/// `init(reservationID:listingID:total:)`, and it stays `internal` instead of
/// becoming `private`.
struct Receipt: Hashable, Sendable, Codable {
    let reservationID: ReservationID
    let listingID: ListingID
    let total: Decimal
    private var auditTrail: [String] = []

    var trail: [String] { auditTrail }

    #if !compiler(>=6.4)
    /// Swift 6.3 and earlier: the synthesized memberwise init includes
    /// `auditTrail` and is therefore `private`, so callers in this module get
    /// "extra arguments … / missing argument for parameter 'from'" (only the
    /// Codable init is visible). 6.4 makes this hand-written init unnecessary.
    init(reservationID: ReservationID, listingID: ListingID, total: Decimal) {
        self.reservationID = reservationID
        self.listingID = listingID
        self.total = total
    }
    #endif

    mutating func note(_ entry: String) {
        auditTrail.append(entry)
    }
}

/// C12 — events fan out to type-erased, Hashable sinks.
enum BookingEvent: Hashable, Sendable {
    case held(ListingID)
    case confirmed(ListingID, ReservationID)
    case cancelled(ListingID, ReservationID)
    case paymentFailed(ListingID, PaymentError)
}

typealias BookingEventSink = E15.AnyEventSink<BookingEvent>

extension ListingID {
    /// `ReservationLock` keys are `Int`s: derive one from the UUID's first 8
    /// bytes (random UUIDs make collisions practically impossible).
    var lockKey: Int {
        withUnsafeBytes(of: rawValue.uuid) { $0.loadUnaligned(as: Int.self) }
    }
}
