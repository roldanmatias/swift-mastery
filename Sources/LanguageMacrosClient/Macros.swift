// Ex 23 — Macro declarations (the public interface clients import).

import Foundation

/// Compile-time validated URL: `#listingURL("https://…")` → non-optional `URL`.
@freestanding(expression)
package macro listingURL(_ string: String) -> URL = #externalMacro(module: "LanguageMacros", type: "ListingURLMacro")

/// Generates an `async throws(Failure)` peer for a completion-handler function.
/// `names: overloaded` tells the compiler the peer has the same base name.
@attached(peer, names: overloaded)
package macro AddAsync() = #externalMacro(module: "LanguageMacros", type: "AddAsyncMacro")
