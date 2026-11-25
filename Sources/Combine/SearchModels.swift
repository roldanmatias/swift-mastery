import Foundation
// Combine exercise — shared vocabulary for the debounced listings search.
//
// One behavior, two implementations: `CombineSearchPipeline` (Combine) and
// `AsyncSearchPipeline` (AsyncSequence). Both must satisfy the same contract
// (see Tests/CombineSearchTests/SearchContractTests.swift).

/// One search hit.
package struct Hit: Sendable, Hashable {
    package var id: Int
    package var title: String
    package init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

/// What a pipeline emits. The query is part of the value so a consumer (and a test)
/// can tell which search a result belongs to.
package enum SearchOutput: Sendable, Equatable {
    case results(query: String, hits: [Hit])
    case failed(query: String, message: String)
}

package protocol SearchService: Sendable {
    func search(_ query: String) async throws -> [Hit]
}

/// Pipeline settings. Plain milliseconds on purpose: Combine's `Scheduler.Stride`
/// and Swift's `Duration` are different types, so a shared number keeps the contract identical.
package struct SearchConfig: Sendable {
    package var debounceMilliseconds: Int
    package init(debounceMilliseconds: Int = 300) { self.debounceMilliseconds = debounceMilliseconds }
}

/// The normalization both pipelines apply before debouncing.
package func normalizeQuery(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
}
