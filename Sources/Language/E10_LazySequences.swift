// Ex 10 — Custom sequences and lazy evaluation.

import Foundation

enum E10 {
    /// Step 1 — every night of a stay, from check-in (inclusive) to check-out
    /// (exclusive). Uses `Calendar` arithmetic, never `+ 86_400`, so nights stay
    /// at local midnight across daylight-saving changes.
    struct StayNights: Sequence {
        let checkIn: Date
        let checkOut: Date
        let calendar: Calendar

        init(checkIn: Date, checkOut: Date, calendar: Calendar = .current) {
            self.checkIn = calendar.startOfDay(for: checkIn)
            self.checkOut = checkOut
            self.calendar = calendar
        }

        struct Iterator: IteratorProtocol {
            var upcoming: Date?
            let checkOut: Date
            let calendar: Calendar

            mutating func next() -> Date? {
                guard let current = upcoming, current < checkOut else { return nil }
                upcoming = calendar.date(byAdding: .day, value: 1, to: current)
                return current
            }
        }

        func makeIterator() -> Iterator {
            Iterator(upcoming: checkIn, checkOut: checkOut, calendar: calendar)
        }
    }

    /// Step 2 — an infinite sequence: nightly prices with a weekend multiplier.
    struct PriceSeries: Sequence, IteratorProtocol {
        let base: Double
        let weekendMultiplier: Double
        private var day = 0

        init(base: Double = 100, weekendMultiplier: Double = 1.25) {
            self.base = base
            self.weekendMultiplier = weekendMultiplier
        }

        mutating func next() -> Double? {
            defer { day += 1 }
            let isWeekend = day % 7 >= 5
            return isWeekend ? base * weekendMultiplier : base
        }
    }
}

// Step 4 — a lazy adapter that stays lazy: conforming to `LazySequenceProtocol`
// means further `.map` / `.filter` calls pick the lazy overloads.
struct LazyChunkedSequence<Base: Sequence>: LazySequenceProtocol {
    let base: Base
    let size: Int

    struct Iterator: IteratorProtocol {
        var base: Base.Iterator
        let size: Int

        mutating func next() -> [Base.Element]? {
            var chunk: [Base.Element] = []
            chunk.reserveCapacity(size)
            while chunk.count < size, let element = base.next() {
                chunk.append(element)
            }
            return chunk.isEmpty ? nil : chunk
        }
    }

    func makeIterator() -> Iterator {
        Iterator(base: base.makeIterator(), size: size)
    }
}

extension LazySequenceProtocol {
    func chunked(by size: Int) -> LazyChunkedSequence<Elements> {
        precondition(size > 0, "chunk size must be positive")
        return LazyChunkedSequence(base: elements, size: size)
    }
}
