// expect: main actor-isolated property 'query' can not be mutated from a nonisolated context
// flags: -swift-version 6 -default-isolation MainActor
final class SearchModel { var query = "" }        // implicitly @MainActor
nonisolated func reset(_ model: SearchModel) { model.query = "" }
