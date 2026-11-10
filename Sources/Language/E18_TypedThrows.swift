// Ex 18 — Typed throws (SE-0413).
//
// `throws(E)` declares the exact error type. Equivalences:
//   throws            ==  throws(any Error)
//   (no throws)       ==  throws(Never)

import Foundation

package enum E18 {
    struct PaymentToken: Sendable, Equatable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    struct Confirmation: Sendable, Equatable {
        let listingID: ListingID
        let amount: Decimal
    }

    static func validate(_ listing: Listing) throws(ListingError) {
        guard listing.nightlyPrice > 0 else { throw .invalidPrice(listing.nightlyPrice) }
        guard listing.maxGuests > 0 else { throw .unavailable(Date.distantPast..<Date.distantPast) }
    }

    static func charge(_ token: PaymentToken, _ amount: Decimal) throws(PaymentError) {
        switch token.value {
        case "declined": throw .declined
        case "fraud": throw .fraudSuspected
        default: return
        }
    }

    /// Step 1 — exhaustive `catch` over a closed error type, no `default`.
    static func describeValidation(_ listing: Listing) -> String {
        do throws(ListingError) {
            try validate(listing)
            return "valid"
        } catch {
            // `error` is `ListingError`, not `any Error`.
            switch error {
            case .notFound: return "not found"
            case .invalidPrice(let price): return "invalid price \(price)"
            case .unavailable: return "unavailable"
            }
        }
    }

    /// Step 2 — compose two error domains by mapping them *explicitly*.
    ///
    /// If you write `try validate(listing)` directly here, it doesn't compile:
    ///   error: thrown expression type 'ListingError' cannot be converted to error type 'BookingError'
    /// Typed throws never converts silently. That's the point.
    static func book(_ listing: Listing, nights: Int, paying token: PaymentToken) throws(BookingError) -> Confirmation {
        do { try validate(listing) } catch { throw .listing(error) }
        let amount = listing.nightlyPrice * Decimal(nights)
        do { try charge(token, amount) } catch { throw .payment(error) }
        return Confirmation(listingID: listing.id, amount: amount)
    }

    /// Step 3 — generic retry that preserves the caller's error type.
    /// With a non-throwing closure, `E` is inferred as `Never` and the call
    /// needs no `try`.
    package static func withRetry<T, E: Error>(attempts: Int, _ operation: () throws(E) -> T) throws(E) -> T {
        precondition(attempts > 0, "attempts must be positive")
        for _ in 1..<attempts {
            do { return try operation() } catch { continue }
        }
        return try operation()   // last attempt: let the error propagate
    }

    /// Step 4 — `rethrows` replaced by typed-throws generics. This is strictly
    /// more expressive: the error type flows through instead of becoming `any Error`.
    static func mapAll<T, U, E: Error>(_ values: [T], _ transform: (T) throws(E) -> U) throws(E) -> [U] {
        var result: [U] = []
        result.reserveCapacity(values.count)
        for value in values { result.append(try transform(value)) }
        return result
    }
}
