// Ex 25 — `borrowing`, `consuming`, `inout`, and the `consume` / `copy` operators.
//
// Default conventions: ordinary parameters are borrowed; `init` parameters and
// setter `newValue` are consumed (they're usually stored). For Copyable types the
// compiler copies as needed; the modifiers make the convention explicit and, for
// `borrowing`/`consuming` params, turn off implicit copies of that parameter.

import Language

enum E25 {
    // MARK: Step 1 — the three conventions with a noncopyable type

    /// Read-only access. The caller still owns the lock afterwards.
    static func inspect(_ lock: borrowing ReservationLock) -> String {
        "listing \(lock.listingID) / token \(lock.token)"
    }

    struct Handoff: ~Copyable {
        let recipient: String
        var lock: ReservationLock
    }

    /// Takes ownership. The caller can't use the lock afterwards.
    static func transfer(_ lock: consuming ReservationLock, to recipient: String) -> Handoff {
        Handoff(recipient: recipient, lock: lock)
    }

    /// Exclusive mutable access. The caller gets the (mutated) lock back.
    static func renew(_ lock: inout ReservationLock) {
        lock.rotateToken()
    }

    // MARK: Step 2 — ownership with a Copyable CoW type

    /// `consuming` parameters are mutable owned values. If the caller passes
    /// `consume cal`, the buffer reference moves in (refcount stays 1), so the
    /// mutation happens in place: no 365-day copy.
    static func appendingBlock(_ calendar: consuming AvailabilityCalendar) -> AvailabilityCalendar {
        calendar.block(0..<1)
        return calendar
    }

    // MARK: Step 3 — `borrowing` Copyable params don't copy implicitly

    //   static func duplicate(_ c: borrowing AvailabilityCalendar) -> AvailabilityCalendar { c }
    //   // error: 'c' is borrowed and cannot be consumed
    static func duplicate(_ calendar: borrowing AvailabilityCalendar) -> AvailabilityCalendar {
        copy calendar
    }

    // MARK: Step 4 — partial consumption (SE-0429)

    /// No `deinit` → you may consume one field out of a consuming `self`; the
    /// remaining fields are destroyed normally.
    struct Hold: ~Copyable {
        var lock: ReservationLock
        var note: String

        consuming func takeLock() -> ReservationLock {
            lock
        }
    }

    /// With a `deinit`, partial consumption is rejected, because `deinit`
    /// needs a whole `self` to run:
    ///
    ///   consuming func takeLock() -> ReservationLock { lock }
    ///   // error: cannot partially consume 'self' when it has a deinitializer
    struct AuditedHold: ~Copyable {
        var lock: ReservationLock
        deinit {}
    }
}
