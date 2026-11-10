// Ex 16 — Parameter packs (variadic generics).
//
// `each T` declares a *type pack*; `repeat X` is a *pack expansion* that
// repeats the pattern X once per element. `(repeat each T)` is a tuple of the
// pack's types. No `Any`, no casts: every element stays statically typed.

import Foundation

package enum E16 {
    // MARK: Step 3 — typed `if let a, let b, let c` for any arity

    private struct Missing: Error {}

    private static func unwrap<U>(_ value: U?) throws(Missing) -> U {
        guard let value else { throw Missing() }
        return value
    }

    /// Returns the unwrapped tuple only if every value is non-nil. A `repeat`
    /// expression can't `return` early, so a throwing helper aborts the
    /// expansion on the first `nil`.
    static func allPresent<each T>(_ values: repeat (each T)?) -> (repeat each T)? {
        do {
            return (repeat try unwrap(each values))
        } catch {
            return nil
        }
    }

    // MARK: Step 1 — one `zip` for any number of sequences

    /// Iterators are mutable, and you can't mutate elements of a tuple pack in
    /// place, so each iterator lives in a small reference box.
    private final class IteratorBox<I: IteratorProtocol> {
        var iterator: I
        init(_ iterator: I) { self.iterator = iterator }
        func next() -> I.Element? { iterator.next() }
    }

    /// Stops at the shortest sequence. (Like the stdlib `zip`, it may pull one
    /// extra element from the longer sequences on the final step.)
    static func zipAll<each S: Sequence>(_ sequences: repeat each S) -> [(repeat (each S).Element)] {
        let boxes = (repeat IteratorBox((each sequences).makeIterator()))
        var result: [(repeat (each S).Element)] = []
        while let row = allPresent(repeat (each boxes).next()) {
            result.append(row)
        }
        return result
    }

    // MARK: Step 2 — a typed validator for N fields

    package struct Rule<Value> {
        package let name: String
        package let isValid: (Value) -> Bool

        package init(name: String, _ isValid: @escaping (Value) -> Bool) {
            self.name = name
            self.isValid = isValid
        }
    }

    package struct FormValidator<each Field> {
        package let rules: (repeat Rule<each Field>)

        package init(_ rules: repeat Rule<each Field>) {
            self.rules = (repeat each rules)
        }

        /// `repeat check(each rules, each values)` expands to one call per field,
        /// in order, pairing the i-th rule with the i-th value. Both packs have
        /// the same shape, which the type system guarantees.
        package func failures(_ values: repeat each Field) -> [String] {
            var failed: [String] = []
            func check<V>(_ rule: Rule<V>, _ value: V) {
                if !rule.isValid(value) { failed.append(rule.name) }
            }
            repeat check(each rules, each values)
            return failed
        }
    }

    // MARK: Step 4 — pack iteration (SE-0408, Swift 6.0)

    /// `for x in repeat each pack` runs the body once per element; inside the
    /// body, `x` has an opened type, so you can only use what the constraint
    /// (`CustomStringConvertible`) gives you.
    static func describeAll<each T: CustomStringConvertible>(_ values: repeat each T) -> [String] {
        var descriptions: [String] = []
        for value in repeat each values {
            descriptions.append(value.description)
        }
        return descriptions
    }

    /// Counts pack elements without knowing their types.
    static func count<each T>(_ values: repeat each T) -> Int {
        var total = 0
        for _ in repeat each values { total += 1 }
        return total
    }
}
