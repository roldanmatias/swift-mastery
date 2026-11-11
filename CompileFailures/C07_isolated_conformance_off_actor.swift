// expect: main actor-isolated conformance of 'ListingCardModel' to 'PriceDisplaying' cannot be used in @concurrent context
// flags: -swift-version 6
protocol PriceDisplaying { func displayPrice() -> String }
@MainActor final class ListingCardModel {}
extension ListingCardModel: @MainActor PriceDisplaying {
    func displayPrice() -> String { "120 USD" }
}
func firstPrice<Card: PriceDisplaying>(_ cards: [Card]) -> String? { cards.first?.displayPrice() }
@MainActor func renderLater(_ card: ListingCardModel) {
    Task.detached { _ = firstPrice([card]) }   // nonisolated: the conformance doesn't exist here
}
