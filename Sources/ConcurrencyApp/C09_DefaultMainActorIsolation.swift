// C09 — Default MainActor isolation (SE-0466, Swift 6.2).
//
// This target is built with `.defaultIsolation(MainActor.self)`: every
// declaration without an explicit isolation is `@MainActor`. That's what Xcode
// 26+ turns on for new app targets, because most app code is UI code. You opt
// *out* with `nonisolated` for the parts that must run anywhere (DTOs, parsers,
// pure logic).

import Foundation

/// Implicitly `@MainActor`, so implicitly `Sendable`: no annotation needed.
package final class SearchModel {
    package private(set) var query = ""
    package private(set) var rows: [ListingRow] = []

    package init() {}

    package func update(query: String, results: [ListingDTO]) {
        self.query = query
        rows = results.map(ListingRow.init)
    }
}

/// Also implicitly `@MainActor`, *including its conformances*: with
/// `InferIsolatedConformances`, `Identifiable`/`Equatable` here are main-actor
/// isolated conformances (SE-0470).
package struct ListingRow: Identifiable, Equatable {
    package let id: Int
    package let title: String
    package let priceText: String

    package init(_ dto: ListingDTO) {
        id = dto.id
        title = dto.title
        priceText = "$\(dto.nightlyCents / 100)"
    }
}

/// Opted out: a wire type must be decodable on any thread, so it and its
/// `Decodable` conformance must be nonisolated.
nonisolated package struct ListingDTO: Decodable, Sendable, Equatable {
    package let id: Int
    package let title: String
    package let nightlyCents: Int

    package init(id: Int, title: String, nightlyCents: Int) {
        self.id = id
        self.title = title
        self.nightlyCents = nightlyCents
    }
}

/// Pure logic opted out of the main actor. Synchronous, so it runs on the caller.
nonisolated package enum PriceMath {
    package static func average(_ cents: [Int]) -> Int {
        cents.isEmpty ? 0 : cents.reduce(0, +) / cents.count
    }
}

/// Reports whether this code is on the main actor right now.
/// No `nonisolated` here: an `isolated` parameter already defines the isolation,
/// and the compiler rejects both ("global function with 'isolated' parameter cannot be 'nonisolated'").
package func isOnMainActor(_ isolation: isolated (any Actor)? = #isolation) -> Bool {
    isolation === MainActor.shared
}
