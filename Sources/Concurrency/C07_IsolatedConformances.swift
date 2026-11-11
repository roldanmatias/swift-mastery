// C07 — Isolated conformances (SE-0470, Swift 6.2).
//
// Before 6.2 a `@MainActor` type couldn't conform to a nonisolated protocol
// with synchronous requirements: you had to mark the witnesses `nonisolated`
// (losing access to state) or use `@preconcurrency` (runtime checks).
// `extension T: @MainActor P` says "this conformance only exists on the main actor".

package protocol PriceDisplaying {
    func displayPrice() -> String
}

@MainActor
package final class ListingCardModel {
    package var nightlyCents: Int
    package var currency: String
    package init(nightlyCents: Int, currency: String = "USD") {
        self.nightlyCents = nightlyCents
        self.currency = currency
    }
}

/// The witness reads main-actor state synchronously, which is only safe because
/// the conformance itself is main-actor isolated.
extension ListingCardModel: @MainActor PriceDisplaying {
    package func displayPrice() -> String { "\(nightlyCents / 100) \(currency)/night" }
}

extension ListingCardModel: @MainActor Equatable {
    package static func == (lhs: ListingCardModel, rhs: ListingCardModel) -> Bool {
        lhs.nightlyCents == rhs.nightlyCents && lhs.currency == rhs.currency
    }
}

/// Generic code can use the isolated conformance as long as it runs on the main actor.
@MainActor
package func renderPrices<Card: PriceDisplaying>(_ cards: [Card]) -> [String] {
    cards.map { $0.displayPrice() }
}

/// A nonisolated generic function works too when it's *synchronous* and called
/// from the main actor: it runs on the caller's actor, so the conformance is valid.
package func firstPrice<Card: PriceDisplaying>(_ cards: [Card]) -> String? {
    cards.first?.displayPrice()
}
