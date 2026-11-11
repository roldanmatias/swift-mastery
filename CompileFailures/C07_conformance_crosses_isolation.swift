// expect: conformance of 'ListingCardModel' to protocol 'PriceDisplaying' crosses into main actor-isolated code
// flags: -swift-version 6
protocol PriceDisplaying { func displayPrice() -> String }
@MainActor final class ListingCardModel: PriceDisplaying {
    var nightlyCents = 12_000
    func displayPrice() -> String { "\(nightlyCents / 100) USD" }
}
