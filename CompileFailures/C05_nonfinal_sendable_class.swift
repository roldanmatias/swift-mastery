// expect: non-final class 'ExchangeRates' cannot conform to the 'Sendable' protocol
// flags: -swift-version 6
class ExchangeRates: Sendable {
    let base = "USD"
}
