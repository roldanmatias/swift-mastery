// C11 — Moving expensive work off the main actor with `@concurrent`.
//
// In a default-MainActor module, heavy work (decoding, image processing,
// conflict resolution) would run on the main thread and cause hitches. Make it
// `@concurrent` and keep everything it touches nonisolated and Sendable.

import Foundation

nonisolated package enum ListingDecoder {
    /// Runs on the global executor. Takes and returns Sendable values only.
    @concurrent
    package static func decode(_ data: Data) async throws -> [ListingDTO] {
        try JSONDecoder().decode([ListingDTO].self, from: data)
    }

    /// Same work, also reporting where it ran (for the tests).
    @concurrent
    package static func decodeReportingThread(_ data: Data) async throws -> (dtos: [ListingDTO], onMainThread: Bool) {
        (try JSONDecoder().decode([ListingDTO].self, from: data), pthread_main_np() != 0)
    }

    /// Fixture generator for tests and benchmarks.
    package static func makePayload(count: Int) throws -> Data {
        let items = (0..<count).map { ["id": $0, "title": "Listing \($0)", "nightlyCents": 10_000 + $0] as [String: Any] }
        return try JSONSerialization.data(withJSONObject: items)
    }
}

/// The UI-facing loader: `@MainActor` by default. It awaits the off-actor work
/// and applies the result on the main actor, with no manual `DispatchQueue` hops.
package final class SearchLoader {
    package let model: SearchModel
    package init(model: SearchModel) { self.model = model }

    package func load(query: String, payload: Data) async throws {
        let dtos = try await ListingDecoder.decode(payload)              // off the main actor
        model.update(query: query, results: dtos)                          // back on the main actor
    }
}
