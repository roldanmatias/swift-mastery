// Combine exercise — the AsyncSequence version of the search pipeline.
//
//   queries ─ map(trim) ─ debounced ─ removingDuplicates ─ mapLatest(search) ─▶ outputs

package struct AsyncSearchPipeline<C: Clock<Duration> & Sendable>: Sendable {
    private let service: any SearchService
    private let clock: C
    private let config: SearchConfig

    package init(service: any SearchService, clock: C, config: SearchConfig = SearchConfig()) {
        self.service = service
        self.clock = clock
        self.config = config
    }

    /// Turns a stream of raw query strings into a stream of search outputs.
    /// Ending the returned stream (or cancelling its consumer) cancels all in-flight work.
    package func outputs<Queries: AsyncSequence & Sendable>(
        for queries: Queries
    ) -> AsyncStream<SearchOutput> where Queries.Element == String, Queries.Failure == Never {
        let service = self.service
        return queries
            .map { normalizeQuery($0) }
            .debounced(for: .milliseconds(config.debounceMilliseconds), clock: clock)
            .removingDuplicates()
            .mapLatest { query in await Self.run(query, on: service) }
    }

    private static func run(_ query: String, on service: any SearchService) async -> SearchOutput {
        if query.isEmpty { return .results(query: query, hits: []) }   // no network call for a blank box
        do {
            return .results(query: query, hits: try await service.search(query))
        } catch {
            return .failed(query: query, message: "\(error)")
        }
    }
}
