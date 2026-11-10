// Ex 12 — `some` vs `any`.
//
// `some P`: ONE concrete type, chosen by the implementation (return position)
//           or by the caller (parameter position), hidden but fixed. Static
//           dispatch, specializable, no box.
// `any P`:  an existential box that can hold ANY conforming type and change at
//           runtime. Dynamic dispatch through the witness table; values bigger
//           than 3 words are heap-allocated.

import Foundation

enum E12 {
    protocol PricingStrategy {
        func price(nights: Int) -> Decimal
    }

    struct StandardPricing: PricingStrategy {
        var nightly: Decimal
        func price(nights: Int) -> Decimal { nightly * Decimal(nights) }
    }

    struct WeeklyDiscount: PricingStrategy {
        var nightly: Decimal
        var percent: Int
        func price(nights: Int) -> Decimal {
            let base = nightly * Decimal(nights)
            return nights >= 7 ? base * Decimal(100 - percent) / 100 : base
        }
    }

    struct SurgePricing: PricingStrategy {
        var nightly: Decimal
        var multiplier: Decimal
        func price(nights: Int) -> Decimal { nightly * multiplier * Decimal(nights) }
    }

    /// Class-constrained, for the `any P & AnyObject` layout comparison.
    final class ReferencePricing: PricingStrategy {
        func price(nights: Int) -> Decimal { Decimal(nights) * 50 }
    }

    enum Season: Sendable, CaseIterable { case low, high, holiday }

    // Step 1 — this does NOT compile:
    //
    //   func strategy(for season: Season) -> some PricingStrategy {
    //       switch season {
    //       case .low: StandardPricing(nightly: 80)
    //       case .high: WeeklyDiscount(nightly: 120, percent: 10)
    //       case .holiday: SurgePricing(nightly: 150, multiplier: 1.5)
    //       }
    //   }
    //   // error: function declares an opaque return type 'some PricingStrategy', but the
    //   //        return statements in its body do not have matching underlying types
    //
    // Fix A: return `any PricingStrategy` (dynamic type, boxed).
    static func anyStrategy(for season: Season) -> any PricingStrategy {
        switch season {
        case .low: StandardPricing(nightly: 80)
        case .high: WeeklyDiscount(nightly: 120, percent: 10)
        case .holiday: SurgePricing(nightly: 150, multiplier: 1.5)
        }
    }

    // Fix B: keep `some` by returning ONE wrapper type that switches internally.
    // Callers keep static dispatch and the API can change the wrapper freely.
    struct SeasonalPricing: PricingStrategy {
        enum Kind {
            case standard(StandardPricing)
            case weekly(WeeklyDiscount)
            case surge(SurgePricing)
        }
        let kind: Kind

        func price(nights: Int) -> Decimal {
            switch kind {
            case .standard(let s): s.price(nights: nights)
            case .weekly(let w): w.price(nights: nights)
            case .surge(let s): s.price(nights: nights)
            }
        }
    }

    static func someStrategy(for season: Season) -> some PricingStrategy {
        switch season {
        case .low: SeasonalPricing(kind: .standard(StandardPricing(nightly: 80)))
        case .high: SeasonalPricing(kind: .weekly(WeeklyDiscount(nightly: 120, percent: 10)))
        case .holiday: SeasonalPricing(kind: .surge(SurgePricing(nightly: 150, multiplier: 1.5)))
        }
    }

    // Step 2 — heterogeneity is what `any` is for.
    static func cheapest(_ strategies: [any PricingStrategy], nights: Int) -> Decimal? {
        strategies.map { $0.price(nights: nights) }.min()
    }

    // Step 3 — implicit opening (SE-0352, Swift 5.7). Passing `any P` to a
    // generic `<S: P>` opens the box and binds `S` to the dynamic type.
    static func audit<S: PricingStrategy>(_ strategy: S) -> String {
        "\(S.self)"
    }

    static func auditExistential(_ strategy: any PricingStrategy) -> String {
        audit(strategy)   // before 5.7: error "protocol 'PricingStrategy' as a type cannot conform to the protocol itself"
    }

    // `some` in parameter position is sugar for an anonymous generic parameter.
    static func quote(_ strategy: some PricingStrategy, nights: Int) -> Decimal {
        strategy.price(nights: nights)
    }

    static func quoteGeneric<S: PricingStrategy>(_ strategy: S, nights: Int) -> Decimal {
        strategy.price(nights: nights)
    }

    // Step 4 — what's left of a PAT after erasure. With
    // `any Repository<Listing>`, `Entity` is known, `Entities` is not: `all()`
    // is *covariantly erased* to its upper bound, `any Collection<Listing>`.
    static func erasedRepositoryCount(_ repository: any E11.Repository<Listing>) -> Int {
        let all: any Collection<Listing> = repository.all()
        return all.count
    }

    static func erasedRepositoryUpsert(_ repository: inout any E11.Repository<Listing>, _ listing: Listing) {
        repository.upsert(listing)   // mutating requirement through an existential: the box is opened in place
    }

    // Step 5 — Swift 6.4 shorthand (SE-0521).
    #if compiler(>=6.4)
    /// `any PricingStrategy?` now means `(any PricingStrategy)?`.
    static func optionalQuote(_ strategy: any PricingStrategy?, nights: Int) -> Decimal? {
        strategy?.price(nights: nights)
    }

    /// `some PricingStrategy?` now means `(some PricingStrategy)?`.
    static func optionalQuoteOpaque(_ strategy: some PricingStrategy?, nights: Int) -> Decimal? {
        strategy?.price(nights: nights)
    }

    /// Compositions still need parentheses: `any (P & Q)?` is accepted…
    static func optionalSendableQuote(_ strategy: any (PricingStrategy & Sendable)?, nights: Int) -> Decimal? {
        strategy?.price(nights: nights)
    }
    // …but `any PricingStrategy & Sendable?` is rejected on purpose: a reader
    // can't tell whether `?` applies to `Sendable` or to the whole composition.
    #else
    static func optionalQuote(_ strategy: (any PricingStrategy)?, nights: Int) -> Decimal? {
        strategy?.price(nights: nights)
    }
    #endif
}

extension E12.StandardPricing: Sendable {}
