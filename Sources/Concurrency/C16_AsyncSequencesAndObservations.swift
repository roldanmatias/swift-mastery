// C16 — Writing an AsyncSequence operator, and observing `@Observable`
// state as an async sequence with `Observations` (SE-0475, Swift 6.2).

import Observation

/// `removeDuplicates()` for any AsyncSequence. Primary associated types
/// (`AsyncSequence<Element, Failure>`, SE-0421) let the failure type flow through:
/// a non-throwing base gives a non-throwing operator.
package struct RemoveDuplicatesSequence<Base: AsyncSequence>: AsyncSequence where Base.Element: Equatable {
    package typealias Element = Base.Element
    package typealias Failure = Base.Failure

    let base: Base

    package struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        var last: Element?

        package mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
            while let element = try await base.next(isolation: actor) {
                if element != last {
                    last = element
                    return element
                }
            }
            return nil
        }
    }

    package func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), last: nil)
    }
}

extension RemoveDuplicatesSequence: Sendable where Base: Sendable {}

extension AsyncSequence where Element: Equatable {
    package func removeDuplicates() -> RemoveDuplicatesSequence<Self> { RemoveDuplicatesSequence(base: self) }
}

/// UI state the rest of the app wants to react to.
@MainActor @Observable
package final class SearchFilters {
    package var maxPriceCents = 50_000
    package var guests = 1
    package init() {}
}

extension SearchFilters {
    /// Every change of `maxPriceCents` as an async sequence. `Observations`
    /// is transactional: several synchronous mutations produce one value.
    package var maxPriceChanges: Observations<Int, Never> {
        Observations { self.maxPriceCents }
    }
}
