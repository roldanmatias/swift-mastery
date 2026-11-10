// Ex 03 — Optionals from first principles.

enum E03 {
    /// `Optional` is "just" this enum. Everything else (`?`, `!`, `if let`,
    /// `?.`, `??`, `nil`) is compiler sugar on top of it.
    enum Maybe<Wrapped> {
        case none
        case some(Wrapped)

        func map<U, E: Error>(_ transform: (Wrapped) throws(E) -> U) throws(E) -> Maybe<U> {
            switch self {
            case .none: .none
            case .some(let value): .some(try transform(value))
            }
        }

        func flatMap<U, E: Error>(_ transform: (Wrapped) throws(E) -> Maybe<U>) throws(E) -> Maybe<U> {
            switch self {
            case .none: .none
            case .some(let value): try transform(value)
            }
        }

        func unwrapped(or fallback: @autoclosure () -> Wrapped) -> Wrapped {
            switch self {
            case .none: fallback()
            case .some(let value): value
            }
        }
    }

    /// Distinguishes the two `nil`s of a `[String: Int?]` lookup.
    enum Lookup: Equatable {
        case missing
        case explicitNil
        case value(Int)
    }

    /// `overrides[key]` has type `Int??`:
    /// - `.none`           → key missing
    /// - `.some(.none)`    → key present, value is nil
    /// - `.some(.some(v))` → key present with a value
    static func lookup(_ overrides: [String: Int?], _ key: String) -> Lookup {
        switch overrides[key] {
        case .none: .missing
        case .some(.none): .explicitNil
        case .some(.some(let value)): .value(value)
        }
    }
}

extension E03.Maybe: ExpressibleByNilLiteral {
    init(nilLiteral: ()) { self = .none }
}

extension E03.Maybe: Equatable where Wrapped: Equatable {}

extension E03.Maybe {
    /// Flattens one level: `Maybe<Maybe<T>>` → `Maybe<T>`.
    func flattened<Inner>() -> E03.Maybe<Inner> where Wrapped == E03.Maybe<Inner> {
        flatMap { $0 }
    }
}

infix operator |?: NilCoalescingPrecedence

/// Our `??`. The right side is an autoclosure: it is only evaluated when the left
/// side is `.none` (short-circuit), exactly like the standard library's `??`.
///
/// `rethrows`, not `throws(E)`: with a generic typed-throws autoclosure,
/// `m |? fallback()` fails to compile with "generic parameter 'E' could not be
/// inferred" (Swift 6.4.2). The stdlib's `??` uses `rethrows` for the same reason.
func |? <T>(lhs: E03.Maybe<T>, rhs: @autoclosure () throws -> T) rethrows -> T {
    switch lhs {
    case .none: try rhs()
    case .some(let value): value
    }
}
