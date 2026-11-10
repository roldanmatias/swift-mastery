// Ex 09 — Key paths.

import Foundation

package enum E09 {
    struct Host: Equatable, Sendable {
        var name: String
    }

    struct Listing: Equatable, Sendable {
        var title: String
        var rating: Double
        var nightlyPrice: Decimal
        var host = Host(name: "Ana")

    }

    /// Step 2 — erases the key path's `Value` type by storing a comparator
    /// closure instead of the key path itself. That's what lets
    /// `[SortRule<Listing>]` mix a `Double` key with a `Decimal` key.
    package struct SortRule<Root> {
        private let compare: (Root, Root) -> ComparisonResult

        package init<Value: Comparable>(_ keyPath: KeyPath<Root, Value>, ascending: Bool = true) {
            compare = { lhs, rhs in
                let (a, b) = (lhs[keyPath: keyPath], rhs[keyPath: keyPath])
                if a == b { return .orderedSame }
                return (a < b) == ascending ? .orderedAscending : .orderedDescending
            }
        }

        package func callAsFunction(_ lhs: Root, _ rhs: Root) -> ComparisonResult {
            compare(lhs, rhs)
        }
    }

    /// Step 3 — functional update through a `WritableKeyPath`.
    static func updating<Root, Value>(
        _ root: Root,
        _ keyPath: WritableKeyPath<Root, Value>,
        to value: Value
    ) -> Root {
        var copy = root
        copy[keyPath: keyPath] = value
        return copy
    }

    /// Step 4 — composition: `\Listing.host` + `\Host.name` = `\Listing.host.name`.
    ///
    /// Swift 6 gotcha: this can't be a `static let`. `KeyPath` is a class and is
    /// not `Sendable` in general (only key-path *literals* that capture nothing
    /// non-Sendable are inferred as `KeyPath<…> & Sendable`, SE-0418), and
    /// `appending(path:)` returns a plain `KeyPath`. So it's a computed property.
    static var hostName: KeyPath<Listing, String> { (\Listing.host).appending(path: \Host.name) }

    /// A literal can be stored globally when typed as `& Sendable`.
    static let titlePath: KeyPath<Listing, String> & Sendable = \Listing.title

    /// Class roots get `ReferenceWritableKeyPath`: writing through it needs no
    /// `inout`, because you mutate the object, not the reference.
    final class Draft {
        var title = ""
    }

    static func setTitle(_ draft: Draft, _ keyPath: ReferenceWritableKeyPath<Draft, String>, _ value: String) {
        draft[keyPath: keyPath] = value
    }
}

extension Sequence {
    /// Step 1 — sort by any `Comparable` property.
    package func sorted<Value: Comparable>(by keyPath: KeyPath<Element, Value>, ascending: Bool = true) -> [Element] {
        sorted { lhs, rhs in
            ascending ? lhs[keyPath: keyPath] < rhs[keyPath: keyPath]
                      : lhs[keyPath: keyPath] > rhs[keyPath: keyPath]
        }
    }

    /// Step 2 — multi-key sort: the first rule that isn't a tie decides.
    package func sorted(by rules: [E09.SortRule<Element>]) -> [Element] {
        sorted { lhs, rhs in
            for rule in rules {
                switch rule(lhs, rhs) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
    }
}
