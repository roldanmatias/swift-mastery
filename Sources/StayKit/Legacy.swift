// StayKit — C3 import and C13 legacy bridge.
//
// StayKit is compiled with warnings-as-errors on Swift 6.4 (Package.swift). The
// legacy bridge is the ONE documented place where deprecation warnings are
// allowed, and it says why.

import Foundation
import Language
import LanguageMacrosClient

/// C3 — imports the legacy JSON payload (Ex 19) into domain listings.
enum ListingImporter {
    static func importListings(from data: Data, city: String) throws -> [Listing] {
        let imported = try JSONDecoder().decode([E19.ImportedListing].self, from: data)
        return imported.map { item in
            Listing(
                id: ListingID(item.id),
                title: item.title,
                city: city,
                nightlyPrice: item.price,
                amenities: Set(item.blocks.flatMap { block -> [String] in
                    if case .amenities(let names) = block { names } else { [] }
                })
            )
        }
    }
}

/// C13 — the legacy callback API. `@AddAsync` (Ex 23) generates
/// `fetchListing(id:) async throws(ListingError) -> Listing`.
final class LegacyCatalogClient: Sendable {
    private let listings: [ListingID: Listing]

    init(_ listings: [Listing]) {
        self.listings = Dictionary(uniqueKeysWithValues: listings.map { ($0.id, $0) })
    }

    @AddAsync
    func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void) {
        let result: Result<Listing, ListingError> = listings[id].map { .success($0) } ?? .failure(.notFound(id))
        DispatchQueue.global().async { completion(result) }
    }

    @available(*, deprecated, message: "Blocks the caller. Use fetchListing(id:) async")
    func fetchListingSync(id: ListingID) -> Listing? {
        listings[id]
    }
}

/// Synchronous callers that haven't migrated yet. `#if` around an attribute
/// (SE-0367) keeps the file building on Swift 6.3, where `@diagnose` doesn't
/// exist (and where StayKit isn't warnings-as-errors).
struct LegacyListingBridge: Sendable {
    let client: LegacyCatalogClient

    #if compiler(>=6.4)
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "StayKit legacy bridge: remove after SwiftMigrator batch 4")
    #endif
    func listing(_ id: ListingID) -> Listing? {
        client.fetchListingSync(id: id)
    }
}
