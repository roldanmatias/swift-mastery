// expect: global function with 'isolated' parameter cannot be 'nonisolated'
// flags: -swift-version 6 -default-isolation MainActor
nonisolated func isOnMainActor(_ isolation: isolated (any Actor)? = #isolation) -> Bool {
    isolation === MainActor.shared
}
