// Ex 23 — Using the macros. Implementations: Sources/LanguageMacros.
//
// Step 3 — `@Observable` (Observation framework) expands, via Xcode's
// "Expand Macro", into these roles:
// - `@attached(member)`: adds `_$observationRegistrar`, `access(keyPath:)`,
//   `withMutation(keyPath:_:)` (plus `shouldNotifyObservers` helpers).
// - `@attached(memberAttribute)`: puts `@ObservationTracked` on every stored
//   `var` (skipping `@ObservationIgnored` ones).
// - `@attached(extension, conformances: Observable)`: adds `: Observable`.
// - `@ObservationTracked` itself is an `@attached(accessor)` + `@attached(peer)`
//   macro: it turns `var title` into a computed property whose get/set call
//   `access`/`withMutation`, with the real storage in a peer `_title`.

import Foundation
import LanguageMacrosClient

enum E23 {
    /// Validated at compile time; a typo here is a build error, not a crash.
    static let homepage = #listingURL("https://example.com/listings")

    // `#listingURL("not a url")`            → error: 'not a url' is not a valid absolute URL
    // `#listingURL("http://example.com")`   → error + fix-it "Replace 'http://' with 'https://'"
    // `#listingURL("https://\(host)")`      → error: requires a static string literal

    final class LegacyCatalog: Sendable {
        private let listings: [ListingID: Listing]

        init(_ listings: [Listing]) {
            self.listings = Dictionary(uniqueKeysWithValues: listings.map { ($0.id, $0) })
        }

        /// The macro generates `fetchListing(id:) async throws(ListingError) -> Listing`.
        @AddAsync
        func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void) {
            let result: Result<Listing, ListingError> = listings[id].map { .success($0) } ?? .failure(.notFound(id))
            DispatchQueue.global().async { completion(result) }
        }
    }
}
