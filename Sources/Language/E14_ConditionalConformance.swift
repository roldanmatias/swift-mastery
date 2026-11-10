// Ex 14 — Conditional conformance and phantom types.
//
// `Tag` is a phantom type parameter: it is never stored, it only exists to make
// `Tagged<Listing, UUID>` and `Tagged<Host, UUID>` different types.
// Every conformance is *conditional* on `RawValue`, never on `Tag`.

import Foundation

package struct Tagged<Tag, RawValue> {
    package let rawValue: RawValue

    package init(_ rawValue: RawValue) {
        self.rawValue = rawValue
    }

    package init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
}

extension Tagged: Equatable where RawValue: Equatable {}
extension Tagged: Hashable where RawValue: Hashable {}

// `Tag` is not stored, so `Sendable` only depends on `RawValue`. That's why
// `Tagged<Listing, UUID>` is Sendable even if the tag type were not.
extension Tagged: Sendable where RawValue: Sendable {}

extension Tagged: Comparable where RawValue: Comparable {
    package static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// Encode as the *bare* raw value: `"5F1B…"`, not `{"rawValue": "5F1B…"}`.
extension Tagged: Decodable where RawValue: Decodable {
    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(RawValue.self))
    }
}

extension Tagged: Encodable where RawValue: Encodable {
    package func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension Tagged: CustomStringConvertible {
    package var description: String { "\(rawValue)" }
}

// String literals need the whole literal-protocol chain spelled out, because
// the default implementations only apply when all literal types are equal.
extension Tagged: ExpressibleByUnicodeScalarLiteral where RawValue: ExpressibleByUnicodeScalarLiteral {
    package init(unicodeScalarLiteral value: RawValue.UnicodeScalarLiteralType) {
        self.init(RawValue(unicodeScalarLiteral: value))
    }
}

extension Tagged: ExpressibleByExtendedGraphemeClusterLiteral
where RawValue: ExpressibleByExtendedGraphemeClusterLiteral {
    package init(extendedGraphemeClusterLiteral value: RawValue.ExtendedGraphemeClusterLiteralType) {
        self.init(RawValue(extendedGraphemeClusterLiteral: value))
    }
}

extension Tagged: ExpressibleByStringLiteral where RawValue: ExpressibleByStringLiteral {
    package init(stringLiteral value: RawValue.StringLiteralType) {
        self.init(RawValue(stringLiteral: value))
    }
}

extension Tagged: ExpressibleByIntegerLiteral where RawValue: ExpressibleByIntegerLiteral {
    package init(integerLiteral value: RawValue.IntegerLiteralType) {
        self.init(RawValue(integerLiteral: value))
    }
}

enum E14 {
    /// Proves the phantom type costs nothing at runtime.
    static var taggedIsFree: Bool {
        MemoryLayout<Tagged<Listing, UUID>>.size == MemoryLayout<UUID>.size
    }

    // Step 2 — this does not compile, which is the point:
    //
    //   func host(for id: HostID) -> Host? { nil }
    //   let listingID = ListingID(UUID())
    //   host(for: listingID)
    //   // error: cannot convert value of type 'ListingID' (aka 'Tagged<Listing, UUID>')
    //   //        to expected argument type 'HostID' (aka 'Tagged<Host, UUID>')
}

// Step 4 — conditional conformance on a type we don't own.
// It compiles, but it's a bad idea: a missing strategy silently becomes a free
// stay (price 0). Prefer making callers handle `nil` explicitly.
extension Optional: E12.PricingStrategy where Wrapped: E12.PricingStrategy {
    func price(nights: Int) -> Decimal {
        self?.price(nights: nights) ?? 0
    }
}
