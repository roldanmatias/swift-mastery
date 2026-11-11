// expect: is not concurrency-safe because it is nonisolated global shared mutable state
// flags: -swift-version 6
var requestCount = 0
