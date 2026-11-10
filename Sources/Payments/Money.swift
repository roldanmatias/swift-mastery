// Ex 05 — this module and `Pricing` both declare `Money` and `String.slug` on purpose.

/// Money as the payments service sees it: integer minor units.
package struct Money: Sendable, Equatable {
    package var cents: Int
    package var currency: String

    package init(cents: Int, currency: String) {
        self.cents = cents
        self.currency = currency
    }
}

extension String {
    /// Collides with `Pricing`'s `String.slug`.
    package var slug: String { "pay-" + lowercased() }
}
