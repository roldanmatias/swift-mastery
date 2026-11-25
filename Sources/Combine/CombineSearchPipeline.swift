// Combine exercise — the Combine version of the search pipeline.
//
//   input ─ map(trim) ─ debounce ─ removeDuplicates ─ map(searchPublisher) ─ switchToLatest ─▶ outputs
//
// `@MainActor`, like any view model that owns a Combine pipeline. That is also what
// keeps Swift 6 happy: Combine's closures (`Future.Promise`, `sink`) are not `Sendable`,
// and a main-actor-isolated closure may capture non-`Sendable` state.

import Combine
import Foundation

@MainActor
package final class CombineSearchPipeline<S: Scheduler> {
    /// Feed raw text here (what `$query` would publish in a view model).
    package let input = PassthroughSubject<String, Never>()
    /// Cold publisher: the *subscriber's* `AnyCancellable` owns the pipeline's lifetime.
    /// (No `share()`: a shared chain stays alive while any one subscriber remains, so
    /// "the view went away" would no longer cancel the search in flight.)
    package let outputs: AnyPublisher<SearchOutput, Never>

    package init(service: any SearchService, scheduler: S, config: SearchConfig = SearchConfig()) {
        let debounce = S.SchedulerTimeType.Stride.milliseconds(config.debounceMilliseconds)
        outputs = input
            .map { normalizeQuery($0) }
            .debounce(for: debounce, scheduler: scheduler)
            .removeDuplicates()
            .map { query in Self.searchPublisher(query, service: service) }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    private static func searchPublisher(_ query: String, service: any SearchService) -> AnyPublisher<SearchOutput, Never> {
        if query.isEmpty {
            return Just(.results(query: query, hits: [])).eraseToAnyPublisher()
        }
        return taskPublisher {
            do {
                return .results(query: query, hits: try await service.search(query))
            } catch {
                return .failed(query: query, message: "\(error)")
            }
        }
    }
}
