// Ex 05 — collides with `Payments.Money` and `Payments`' `String.slug`.
import Foundation

/// Money as the pricing engine sees it: exact decimal amount.
package struct Money: Sendable, Equatable {
    package var amount: Decimal

    package init(amount: Decimal) {
        self.amount = amount
    }
}

extension String {
    package var slug: String { "price-" + lowercased() }
}
