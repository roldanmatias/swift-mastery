// Ex 13 — Generic constraints and constrained extensions.

import Foundation

extension Collection where Element: AdditiveArithmetic {
    func sum() -> Element { reduce(.zero, +) }
}

extension Sequence where Element == Listing {
    func averagePrice() -> Decimal {
        var total: Decimal = 0
        var count = 0
        for listing in self {
            total += listing.nightlyPrice
            count += 1
        }
        return count == 0 ? 0 : total / Decimal(count)
    }
}

enum E13 {
    static func mergeUnique<A: Sequence, B: Sequence>(_ a: A, _ b: B) -> [A.Element]
    where A.Element == B.Element, A.Element: Hashable {
        var seen = Set<A.Element>()
        var result: [A.Element] = []
        for element in a where seen.insert(element).inserted { result.append(element) }
        for element in b where seen.insert(element).inserted { result.append(element) }
        return result
    }

    struct Median<Element> {
        let value: Element?
        /// Which implementation ran, so tests can see overload resolution.
        let strategy: String
    }

    // MARK: The trap — overloads are chosen at compile time

    /// Inside this function the compiler only knows `C: Collection`, so it
    /// statically picks the `Collection` overload of `median()`, even when the
    /// caller passes an `Array`. Constrained extensions are NOT dynamic dispatch.
    static func report<C: Collection>(_ values: C) -> Median<C.Element> where C.Element: Comparable {
        values.median()
    }

    // MARK: The fix — a customization point (a protocol *requirement*)

    /// A requirement gets a witness-table entry. When a type conforms, the most
    /// specific default available *at conformance time* is recorded, so
    /// `Array` gets the RandomAccessCollection version, even through a generic.
    protocol MedianComputable: Collection where Element: Comparable {
        func fastMedian() -> Median<Element>
    }

    static func reportFixed<C: MedianComputable>(_ values: C) -> Median<C.Element> {
        values.fastMedian()
    }
}

extension Collection where Element: Comparable {
    /// Generic version: walks to the middle index, O(n) after sorting.
    func median() -> E13.Median<Element> {
        guard !isEmpty else { return .init(value: nil, strategy: "Collection") }
        let sorted = self.sorted()
        return .init(value: sorted[sorted.index(sorted.startIndex, offsetBy: sorted.count / 2)], strategy: "Collection")
    }
}

extension RandomAccessCollection where Element: Comparable {
    /// More specific overload: O(1) index arithmetic.
    func median() -> E13.Median<Element> {
        guard !isEmpty else { return .init(value: nil, strategy: "RandomAccessCollection") }
        let sorted = self.sorted()
        return .init(value: sorted[sorted.count / 2], strategy: "RandomAccessCollection")
    }
}

extension E13.MedianComputable {
    func fastMedian() -> E13.Median<Element> {
        .init(value: median().value, strategy: "Collection")
    }
}

extension E13.MedianComputable where Self: RandomAccessCollection {
    func fastMedian() -> E13.Median<Element> {
        .init(value: median().value, strategy: "RandomAccessCollection")
    }
}

extension Array: E13.MedianComputable where Element: Comparable {}
extension Set: E13.MedianComputable where Element: Comparable {}
