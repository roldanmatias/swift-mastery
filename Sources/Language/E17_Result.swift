// Ex 17 — `Result` as a value.

import Foundation

extension Result {
    /// Both succeed → a pair; otherwise the first failure.
    func zip<Other>(_ other: Result<Other, Failure>) -> Result<(Success, Other), Failure> {
        flatMap { success in other.map { (success, $0) } }
    }

    /// Fail fast: stops evaluating thunks at the first failure.
    static func collect(_ thunks: [() -> Result<Success, Failure>]) -> Result<[Success], Failure> {
        var values: [Success] = []
        values.reserveCapacity(thunks.count)
        for thunk in thunks {
            switch thunk() {
            case .success(let value): values.append(value)
            case .failure(let error): return .failure(error)
            }
        }
        return .success(values)
    }

    /// Eagerly computed results, same semantics.
    static func collect(_ results: [Result<Success, Failure>]) -> Result<[Success], Failure> {
        collect(results.map { result in { result } })
    }

    /// `Never` as the failure type: the compiler now *knows* this can't fail,
    /// so `get()` needs no `try`.
    func recover(_ transform: (Failure) -> Success) -> Result<Success, Never> {
        switch self {
        case .success(let value): .success(value)
        case .failure(let error): .success(transform(error))
        }
    }
}

package enum E17 {
    /// A legacy callback API (the kind SwiftMigrator migrates).
    package final class LegacyListingAPI: Sendable {
        private let listings: [ListingID: Listing]

        package init(_ listings: [Listing]) {
            self.listings = Dictionary(uniqueKeysWithValues: listings.map { ($0.id, $0) })
        }

        package func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void) {
            let result: Result<Listing, ListingError> = listings[id].map { .success($0) } ?? .failure(.notFound(id))
            DispatchQueue.global().async { completion(result) }
        }

        /// Step 3 — bridge to async WITHOUT losing the error type.
        /// `withCheckedThrowingContinuation` would erase the error to `any Error`;
        /// resuming with a `Result` and calling `get()` keeps `ListingError`.
        package func fetchListing(id: ListingID) async throws(ListingError) -> Listing {
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Listing, ListingError>, Never>) in
                fetchListing(id: id) { continuation.resume(returning: $0) }
            }
            return try result.get()
        }

        /// Deprecated entry point used by Ex 20 (`@diagnose`).
        @available(*, deprecated, renamed: "fetchListing(id:)", message: "Use the async version")
        package func fetchListingLegacy(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void) {
            fetchListing(id: id, completion: completion)
        }
    }

    static func validatePrice(_ listing: Listing) throws(ListingError) -> Listing {
        guard listing.nightlyPrice > 0 else { throw .invalidPrice(listing.nightlyPrice) }
        return listing
    }

    /// Step 4 — `Result(catching:)` keeps the closure's typed error.
    static func validated(_ listing: Listing) -> Result<Listing, ListingError> {
        Result { () throws(ListingError) -> Listing in try validatePrice(listing) }
    }
}
