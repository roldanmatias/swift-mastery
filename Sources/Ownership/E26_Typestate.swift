// Ex 26 — Typestate with noncopyable types: the reservation state machine.

struct DraftInfo: Hashable, Sendable {
    let listingID: Int
    let guest: String
    let nights: Int

}

struct PaymentToken: Hashable, Sendable {
    let value: String
    var isValid: Bool { !value.isEmpty && value != "declined" }
    init(_ value: String) { self.value = value }
}

enum RejectReason: Hashable, Sendable {
    case paymentDeclined
    case lockUnavailable
    case invalidTransition(from: String, action: String)
}

enum E26 {
    // MARK: A — noncopyable enum

    enum Reservation: ~Copyable {
        case draft(DraftInfo)
        case confirmed(DraftInfo, paymentRef: String, lock: ReservationLock)
        case cancelled(DraftInfo, reason: String, receipt: ReleaseReceipt?)

        /// `switch consume self`: we own `self`, so the payloads (including the
        /// noncopyable lock) can be bound and moved into the new state.
        consuming func confirm(payment: PaymentToken) -> Transition {
            switch consume self {
            case .draft(let info):
                guard payment.isValid else {
                    return .rejected(.draft(info), reason: .paymentDeclined)
                }
                do {
                    let lock = try ReservationLock(acquiring: info.listingID)
                    return .moved(.confirmed(info, paymentRef: payment.value, lock: lock))
                } catch {
                    return .rejected(.draft(info), reason: .lockUnavailable)
                }
            case let .confirmed(info, ref, lock):
                return .rejected(.confirmed(info, paymentRef: ref, lock: lock),
                                 reason: .invalidTransition(from: "confirmed", action: "confirm"))
            case let .cancelled(info, reason, receipt):
                return .rejected(.cancelled(info, reason: reason, receipt: receipt),
                                 reason: .invalidTransition(from: "cancelled", action: "confirm"))
            }
        }

        consuming func cancel(reason: String) -> Transition {
            switch consume self {
            case .draft(let info):
                return .moved(.cancelled(info, reason: reason, receipt: nil))
            case let .confirmed(info, _, lock):
                return .moved(.cancelled(info, reason: reason, receipt: lock.release()))
            case let .cancelled(info, oldReason, receipt):
                return .rejected(.cancelled(info, reason: oldReason, receipt: receipt),
                                 reason: .invalidTransition(from: "cancelled", action: "cancel"))
            }
        }

        /// Borrowing switch (SE-0432): read-only, no bindings that would move.
        var status: String {
            switch self {
            case .draft: "draft"
            case .confirmed: "confirmed"
            case .cancelled: "cancelled"
            }
        }
    }

    /// Why not `throws`? `Error` requires `Copyable` (and `Sendable`), so an
    /// error can't carry the noncopyable reservation back to the caller. A
    /// failed *consuming* transition must therefore return the value.
    enum Transition: ~Copyable {
        case moved(Reservation)
        case rejected(Reservation, reason: RejectReason)

        var rejectReason: RejectReason? {
            switch self {
            case .moved: nil
            case .rejected(_, let reason): reason
            }
        }

        /// Either way, you get a reservation back.
        consuming func reservation() -> Reservation {
            switch consume self {
            case .moved(let reservation): reservation
            case .rejected(let reservation, _): reservation
            }
        }
    }

    // MARK: B — typestate structs

    struct ConfirmError: Error, Hashable {
        let reason: RejectReason
        /// The draft's data is Copyable, so the caller can rebuild a draft.
        let draft: DraftInfo
    }

    struct DraftReservation: ~Copyable {
        let info: DraftInfo
        init(_ info: DraftInfo) { self.info = info }

        consuming func confirm(payment: PaymentToken) throws(ConfirmError) -> ConfirmedReservation {
            guard payment.isValid else { throw ConfirmError(reason: .paymentDeclined, draft: info) }
            do {
                let lock = try ReservationLock(acquiring: info.listingID)
                return ConfirmedReservation(info: info, paymentRef: payment.value, lock: lock)
            } catch {
                throw ConfirmError(reason: .lockUnavailable, draft: info)
            }
        }
        // No `cancel()` here: cancelling a draft is just dropping it.
    }

    struct ConfirmedReservation: ~Copyable {
        let info: DraftInfo
        let paymentRef: String
        let lock: ReservationLock

        var lockToken: UInt64 { lock.token }

        consuming func cancel(reason: String) -> CancelledReservation {
            CancelledReservation(info: info, reason: reason, receipt: lock.release())
        }
    }

    /// Terminal state: nothing left to enforce, so it's an ordinary Copyable value.
    struct CancelledReservation: Hashable, Sendable {
        let info: DraftInfo
        let reason: String
        let receipt: ReleaseReceipt
    }

    // Illegal transitions in B don't compile:
    //
    //   let draft = DraftReservation(info)
    //   draft.cancel(reason: "x")
    //   // error: value of type 'DraftReservation' has no member 'cancel'
    //
    //   let confirmed = try draft.confirm(payment: token)
    //   _ = confirmed.cancel(reason: "a"); _ = confirmed.cancel(reason: "b")
    //   // error: 'confirmed' consumed more than once
}
