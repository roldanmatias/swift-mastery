// C13 — `async let` vs task groups: fan-out, fail-fast and "first one wins".

package struct PriceBreakdown: Sendable, Equatable {
    package let nightlyCents: Int
    package let feesCents: Int
    package let taxCents: Int
    package var totalCents: Int { nightlyCents + feesCents + taxCents }
}

package enum QuoteError: Error, Equatable, Sendable {
    case feesUnavailable
    case noMirrorResponded
}

/// The three services a quote depends on. Each call is independent.
package struct QuoteServices: Sendable {
    package var nightly: @Sendable (Int) async throws -> Int
    package var fees: @Sendable (Int) async throws -> Int
    package var tax: @Sendable (Int) async throws -> Int

    package init(
        nightly: @escaping @Sendable (Int) async throws -> Int,
        fees: @escaping @Sendable (Int) async throws -> Int,
        tax: @escaping @Sendable (Int) async throws -> Int
    ) {
        self.nightly = nightly
        self.fees = fees
        self.tax = tax
    }
}

package struct QuoteAggregator: Sendable {
    package let services: QuoteServices
    package init(services: QuoteServices) { self.services = services }

    /// `async let`: a fixed number of child tasks with different result types.
    /// The children start immediately; the `await`s collect them **in the order
    /// written**, so a fast failure in `fees` isn't seen while `nightly` is still
    /// running. Unawaited children are cancelled and awaited at scope exit.
    package func quote(listingID: Int) async throws -> PriceBreakdown {
        async let nightly = services.nightly(listingID)
        async let fees = services.fees(listingID)
        async let tax = services.tax(listingID)
        return try await PriceBreakdown(nightlyCents: nightly, feesCents: fees, taxCents: tax)
    }

    /// A throwing task group delivers results **in completion order**, so the
    /// first error ends the group, and leaving the group cancels the siblings.
    package func quoteFailFast(listingID: Int) async throws -> PriceBreakdown {
        enum Part { case nightly(Int), fees(Int), tax(Int) }
        return try await withThrowingTaskGroup(of: Part.self) { group in
            let services = self.services
            group.addTask { .nightly(try await services.nightly(listingID)) }
            group.addTask { .fees(try await services.fees(listingID)) }
            group.addTask { .tax(try await services.tax(listingID)) }

            var nightly = 0, fees = 0, tax = 0
            for try await part in group {
                switch part {
                case .nightly(let value): nightly = value
                case .fees(let value): fees = value
                case .tax(let value): tax = value
                }
            }
            return PriceBreakdown(nightlyCents: nightly, feesCents: fees, taxCents: tax)
        }
    }

    /// Hedged request: ask every mirror, keep the first success, cancel the rest.
    package static func firstResponse(
        from mirrors: [@Sendable () async throws -> Int]
    ) async throws -> Int {
        try await withThrowingTaskGroup(of: Int?.self) { group in
            for mirror in mirrors {
                group.addTask { try? await mirror() }       // a failing mirror yields nil
            }
            while let result = try await group.next() {
                if let value = result {
                    group.cancelAll()
                    return value
                }
            }
            throw QuoteError.noMirrorResponded
        }
    }
}
