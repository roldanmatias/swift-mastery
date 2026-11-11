// C01 — Isolation domains: where does this code run?
//
// Three kinds of isolation domain exist: an actor instance, a global actor
// (MainActor, or one you declare) and "nonisolated" (no actor at all).
// `#isolation` (SE-0420) is a macro that expands to the isolation of the code
// that *evaluates* it, so used as a default argument it captures the caller's.

/// Names the isolation domain of the caller.
///
/// The `isolated` parameter makes this function run on that actor; the default
/// `#isolation` is evaluated at the call site. It's synchronous, so calling it
/// never hops or suspends.
package func isolationLabel(_ isolation: isolated (any Actor)? = #isolation) -> String {
    guard let isolation else { return "nonisolated" }
    if isolation === MainActor.shared { return "MainActor" }
    return String(describing: type(of: isolation))
}

/// A listing's nightly prices. Each instance is its own isolation domain.
package actor PriceCalendar {
    private var nightly: [Int: Int] = [:]   // day → price in cents

    package init(prices: [Int: Int] = [:]) { nightly = prices }

    package func setPrice(_ cents: Int, day: Int) { nightly[day] = cents }
    package func price(day: Int) -> Int? { nightly[day] }

    /// Actor-isolated, so `#isolation` resolves to `self`.
    package func whereAmI() -> String { isolationLabel() }

    /// Calling a *synchronous* nonisolated function from an actor method runs it
    /// on the actor (no hop): sync code always runs where its caller runs.
    package func whereDoesSyncHelperRun() -> String { syncHelper() }

    /// Crossing into another actor's domain is always an `await`, even between
    /// two instances of the same actor type.
    package func copyPrices(from other: PriceCalendar, days: ClosedRange<Int>) async {
        for day in days {
            if let cents = await other.price(day: day) { nightly[day] = cents }
        }
    }

    /// Two instances, two domains: `self` is isolated here, `other` is not.
    package func isSameDomain(as other: PriceCalendar) -> Bool { self === other }
}

/// No isolation of its own: it inherits the caller's.
package func syncHelper(_ isolation: isolated (any Actor)? = #isolation) -> String {
    isolationLabel(isolation)
}

@MainActor package func mainActorLabel() -> String { isolationLabel() }
