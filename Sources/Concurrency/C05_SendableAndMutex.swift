// C05 — Sendable, from "free" to "last resort".
//
// The ladder, safest first:
//   1. value type with Sendable members          → `struct Quote: Sendable`
//   2. final class with only `let` Sendable state → `final class ExchangeRates: Sendable`
//   3. isolate it                                 → actor / @MainActor / global actor
//   4. synchronize with Mutex (Synchronization)   → `final class RateLimiter: Sendable`
//   5. you own a lock the compiler can't see      → `@unchecked Sendable` + a comment

import Foundation
import Synchronization

// 1. Value type. Implicitly Sendable when internal; spelled out because
//    `package`/`public` types don't get implicit Sendable across modules.
package struct Quote: Sendable, Hashable {
    package let listingID: Int
    package let nights: Int
    package let totalCents: Int
    package init(listingID: Int, nights: Int, totalCents: Int) {
        self.listingID = listingID
        self.nights = nights
        self.totalCents = totalCents
    }
}

// 2. Immutable final class: identity without shared mutable state.
package final class ExchangeRates: Sendable {
    package let base: String
    package let rates: [String: Decimal]
    package init(base: String, rates: [String: Decimal]) { self.base = base; self.rates = rates }

    package func convert(cents: Int, to currency: String) -> Int? {
        guard let rate = rates[currency] else { return nil }
        return NSDecimalNumber(decimal: Decimal(cents) * rate).intValue
    }
}

// 4. Mutex: synchronous, non-async-safe-to-hold lock whose state is *inside* it,
//    so the compiler proves every access is locked. `Mutex` is `~Copyable` and
//    Sendable, so a `let` of it keeps the class Sendable.
package final class RateLimiter: Sendable {
    private struct State { var tokens: Int; var granted = 0; var rejected = 0 }
    private let state: Mutex<State>

    package init(capacity: Int) { state = Mutex(State(tokens: capacity)) }

    /// Synchronous on purpose: no `await` can happen while the lock is held.
    package func tryAcquire() -> Bool {
        state.withLock { state in
            guard state.tokens > 0 else { state.rejected += 1; return false }
            state.tokens -= 1
            state.granted += 1
            return true
        }
    }

    package var stats: (granted: Int, rejected: Int) {
        state.withLock { ($0.granted, $0.rejected) }
    }
}

// 5. Last resort. The compiler trusts you; nothing checks it.
/// `@unchecked Sendable`: every access to `counts` happens while holding `lock`.
/// Remove once callers can move to `RateLimiter`-style `Mutex` (needs macOS 15+).
package final class LegacyMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    package init() {}

    package func record(_ event: String) {
        lock.lock(); defer { lock.unlock() }
        counts[event, default: 0] += 1
    }

    package func count(of event: String) -> Int {
        lock.withLock { counts[event, default: 0] }
    }
}

/// `@Sendable` closures may only capture Sendable values, and only *immutably*:
/// a captured `var` would be shared mutable state.
package func makeQuoteFormatter(currency: String, rates: ExchangeRates) -> @Sendable (Quote) -> String {
    { quote in
        let converted = rates.convert(cents: quote.totalCents, to: currency) ?? quote.totalCents
        return "\(quote.nights) nights · \(converted) \(currency)"
    }
}
