// expect: stored property 'tokens' of 'Sendable'-conforming class 'RateLimiter' is mutable
// flags: -swift-version 6
final class RateLimiter: Sendable {
    var tokens = 10
}
