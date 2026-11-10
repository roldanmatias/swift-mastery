// Ex 06 — Copy-on-write by hand.

import Foundation

package struct DayInfo: Equatable, Sendable {
    package var isAvailable: Bool
    package var price: Decimal

    package init(isAvailable: Bool = true, price: Decimal) {
        self.isAvailable = isAvailable
        self.price = price
    }
}

/// 365 days of availability. Copying is O(1) (one retain); the buffer is
/// duplicated lazily, only when a *shared* buffer is about to be mutated.
package struct AvailabilityCalendar: Equatable, Sendable {
    // `final`: `isKnownUniquelyReferenced` needs a native Swift class, and
    // `final` also guarantees no subclass can add shared state behind our back.
    // `@unchecked Sendable` is sound here because the storage is never mutated
    // unless it's uniquely referenced (so no other thread can observe it).
    private final class Storage: @unchecked Sendable {
        package var days: [DayInfo]
        package init(days: [DayInfo]) { self.days = days }
    }

    private var storage: Storage

    package init(days: Int = 365, price: Decimal) {
        storage = Storage(days: Array(repeating: DayInfo(price: price), count: days))
    }

    package init(days: [DayInfo]) {
        storage = Storage(days: days)
    }

    /// Test hook: identity of the underlying buffer.
    package var _storageID: ObjectIdentifier { ObjectIdentifier(storage) }

    package var count: Int { storage.days.count }
    package var days: [DayInfo] { storage.days }

    /// The heart of CoW: clone only if someone else also references the buffer.
    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(days: storage.days)
        }
    }

    /// `_modify` yields the element in place, so `calendar[3].price += 10` is a
    /// single access with no temporary copy of the element or the buffer.
    /// A plain `set` would do get → mutate a copy → set.
    package subscript(day: Int) -> DayInfo {
        get { storage.days[day] }
        _modify {
            makeUnique()
            yield &storage.days[day]
        }
    }

    package mutating func block(_ range: Range<Int>) {
        makeUnique()
        for day in range {
            storage.days[day].isAvailable = false
        }
    }

    package mutating func unblock(_ range: Range<Int>) {
        makeUnique()
        for day in range {
            storage.days[day].isAvailable = true
        }
    }

    package func isAvailable(_ range: Range<Int>) -> Bool {
        range.allSatisfy { storage.days.indices.contains($0) && storage.days[$0].isAvailable }
    }

    package mutating func setPrice(_ price: Decimal, for range: Range<Int>) {
        makeUnique()
        for day in range {
            storage.days[day].price = price
        }
    }

    package var availableDays: Int { storage.days.lazy.filter(\.isAvailable).count }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage === rhs.storage || lhs.storage.days == rhs.storage.days
    }
}

enum E06 {
    /// Step 4 — the CoW-defeating bug. Taking a snapshot (an "undo history") on
    /// every iteration is O(1) per snapshot, but it makes the buffer shared
    /// again right before each mutation, so *every* mutation copies all days:
    /// O(n²) total. (A single extra reference taken *once* only costs one copy:
    /// after that copy the buffer is unique again.)
    static func repriceWithHistory(
        _ calendar: inout AvailabilityCalendar,
        to price: Decimal
    ) -> (copies: Int, history: [AvailabilityCalendar]) {
        var history: [AvailabilityCalendar] = []
        var copies = 0
        for day in 0..<calendar.count {
            history.append(calendar)                // just a retain…
            let before = calendar._storageID
            calendar[day].price = price             // …but now the buffer is shared → full copy
            if calendar._storageID != before { copies += 1 }
        }
        return (copies, history)
    }

    /// The fix: one bulk mutation (one uniqueness check, at most one copy), and
    /// don't hold extra references while mutating.
    static func repriceFast(_ calendar: inout AvailabilityCalendar, to price: Decimal) {
        calendar.setPrice(price, for: 0..<calendar.count)
    }
}
