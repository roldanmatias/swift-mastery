// Ex 20 — Scoped warning control with `@diagnose` (SE-0522, Swift 6.4).
//
// This target is compiled with `.treatAllWarnings(as: .error)` (Package.swift),
// the equivalent of `-warnings-as-errors`. The legacy adapter must keep calling
// a deprecated API during the migration. Diagnostic group (from
// `-print-diagnostic-groups` / the `[#…]` suffix): `DeprecatedDeclaration`.

import Foundation
import Language

#if compiler(>=6.4)

/// Type-level scope: inside this struct, deprecation warnings are warnings
/// again (not errors), but the rest of the module is still warnings-as-errors.
@diagnose(DeprecatedDeclaration, as: warning, reason: "Remove after SwiftMigrator batch 3")
struct LegacyListingAdapter: Sendable {
    let api: E17.LegacyListingAPI

    /// Nested refinement: fully silenced for this one method. The `reason:` is
    /// a static string so tools can grep it into a migration-debt report
    /// (scripts/diagnose-report.sh).
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Bridge for callers not yet on async")
    func fetch(_ id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void) {
        api.fetchListingLegacy(id: id, completion: completion)
    }

    // Putting it back to error in a nested scope:
    //
    //   @diagnose(DeprecatedDeclaration, as: error)
    //   func strictFetch(_ id: ListingID) {
    //       api.fetchListingLegacy(id: id) { _ in }
    //       // error: 'fetchListingLegacy(id:completion:)' is deprecated: Use the async version [#DeprecatedDeclaration]
    //   }
    //
    // And the limit: `@diagnose` only controls WARNINGS. This is still an error:
    //
    //   @diagnose(DeprecatedDeclaration, as: ignored)
    //   func broken() -> Int { "not an int" }
    //   // error: cannot convert return expression of type 'String' to return type 'Int'
}

#else

/// Swift 6.3 fallback: no `@diagnose`, and the target isn't warnings-as-errors
/// on 6.3 (see Package.swift), so the deprecation is just a warning.
struct LegacyListingAdapter: Sendable {
    let api: E17.LegacyListingAPI
    func fetch(_ id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void) {
        api.fetchListing(id: id, completion: completion)
    }
}

#endif
