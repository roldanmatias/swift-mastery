// Ex 28 — Noncopyable types conforming to Equatable / Comparable / Hashable
// (SE-0499, Swift 6.4).
//
// Findings on Swift 6.4.2 (verified with the compiler):
// - `Equatable`, `Comparable`, `Hashable` accept `~Copyable` types, and the
//   compiler SYNTHESIZES `==` and `hash(into:)` for noncopyable structs.
// - `Hasher.combine(_:)` takes a borrowed noncopyable value.
// - `x == nil` works for `Optional<Noncopyable>` (it always did, via
//   `_OptionalNilComparisonType`), but `Optional == Optional` for noncopyable
//   `Wrapped` is NOT available yet.
// - `CustomStringConvertible` is still Copyable-only in 6.4.2, so noncopyable
//   values can't be interpolated or passed to `String(describing:)`.
// - `Set` / `Dictionary` still require `Copyable` elements/keys.

#if compiler(>=6.4)

/// Synthesized `Equatable` + `Hashable` (all stored properties are Hashable).
struct SecretToken: ~Copyable, Hashable {
    private let bytes: [UInt8]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Redacted text (can't be `description`: see the findings above).
    var redacted: String { "SecretToken(\(bytes.count) bytes, ••••)" }
}

/// Hand-written conformance: requirements take `borrowing` parameters, so
/// comparing never copies (or consumes) the operands.
struct APIKey: ~Copyable, Hashable {
    let key: String
    let scope: String

    /// Keys are equal regardless of scope casing.
    static func == (lhs: borrowing APIKey, rhs: borrowing APIKey) -> Bool {
        lhs.key == rhs.key && lhs.scope.lowercased() == rhs.scope.lowercased()
    }

    /// Must hash exactly what `==` compares (a == b ⇒ hash(a) == hash(b)).
    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(scope.lowercased())
    }
}

extension E27.Box: Equatable where T: Equatable & ~Copyable {
    static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.value == rhs.value
    }
}

extension E27.Box: Hashable where T: Hashable & ~Copyable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

/// Locks ordered by acquisition (token).
extension ReservationLock: Comparable {
    package static func == (lhs: borrowing ReservationLock, rhs: borrowing ReservationLock) -> Bool {
        lhs.token == rhs.token
    }

    package static func < (lhs: borrowing ReservationLock, rhs: borrowing ReservationLock) -> Bool {
        lhs.token < rhs.token
    }
}

enum E28 {
    /// Returns the *token*, not the lock: both locks are borrowed, and handing
    /// one back would require consuming (moving) it out of the caller.
    static func earliest(_ a: borrowing ReservationLock, _ b: borrowing ReservationLock) -> UInt64 {
        a < b ? a.token : b.token
    }

    static func hashOf<T: Hashable & ~Copyable>(_ value: borrowing T) -> Int {
        var hasher = Hasher()
        hasher.combine(value)
        return hasher.finalize()
    }

    // Step 6 — recorded errors (Swift 6.4.2):
    //   let set: Set<SecretToken> = []
    //   // error: type 'SecretToken' does not conform to protocol 'Copyable'
    //   let dict: [SecretToken: Int] = [:]
    //   // error: type 'SecretToken' does not conform to protocol 'Copyable'
    //   let a: SecretToken? = …, b: SecretToken? = …;  a == b
    //   // error: operator function '==' requires that 'SecretToken' conform to 'Copyable'
    //   "\(token)"
    //   // error: no exact matches in call to instance method 'appendInterpolation'
}

#endif
