// Ex 02 — Enums with associated values and pattern matching.

import Foundation

package enum E02 {
    /// `indirect` stores recursive payloads in a heap box, so the enum has a
    /// finite size even though it contains itself.
    package indirect enum PricingRule: Equatable, Sendable {
        case nightly(Decimal)
        case cleaningFee(Decimal)
        case percentOff(Int, PricingRule)
        case combined(PricingRule, PricingRule)
        case ifStayAtLeast(nights: Int, then: PricingRule, else: PricingRule)
    }

    /// A custom pattern type: `case StayLength.weekly:` matches an `Int`.
    struct StayLength: Sendable {
        let nights: ClosedRange<Int>
        init(_ nights: ClosedRange<Int>) { self.nights = nights }

        static let short = StayLength(1...6)
        static let weekly = StayLength(7...27)
        static let monthly = StayLength(28...Int.max)

        /// `switch value { case pattern: … }` calls `pattern ~= value`.
        static func ~= (pattern: StayLength, value: Int) -> Bool {
            pattern.nights.contains(value)
        }
    }

    static func describe(nights: Int) -> String {
        switch nights {
        case StayLength.short: "short stay"
        case StayLength.weekly: "weekly stay"
        case StayLength.monthly: "monthly stay"
        default: "invalid"
        }
    }

    /// `for case` filters and destructures in one step.
    static func totalCleaningFees(_ rules: [PricingRule]) -> Decimal {
        var total: Decimal = 0
        for case .cleaningFee(let fee) in rules {
            total += fee
        }
        return total
    }
}

extension E02.PricingRule {
    package func total(nights: Int) -> Decimal {
        switch self {
        case .nightly(let price):
            price * Decimal(nights)
        case .cleaningFee(let fee):
            fee
        case let .percentOff(percent, rule):
            rule.total(nights: nights) * Decimal(100 - percent) / 100
        case let .combined(lhs, rhs):
            lhs.total(nights: nights) + rhs.total(nights: nights)
        case let .ifStayAtLeast(minimum, then, otherwise):
            nights >= minimum ? then.total(nights: nights) : otherwise.total(nights: nights)
        }
    }

    /// Bottom-up rewrite: simplify the children first, then match the parent
    /// with nested patterns.
    package func simplified() -> E02.PricingRule {
        switch self {
        case .nightly, .cleaningFee:
            return self
        case let .percentOff(percent, rule):
            return Self.simplifyPercent(percent, rule.simplified())
        case let .combined(lhs, rhs):
            return Self.simplifyCombined(lhs.simplified(), rhs.simplified())
        case let .ifStayAtLeast(nights, then, otherwise):
            let (a, b) = (then.simplified(), otherwise.simplified())
            return a == b ? a : .ifStayAtLeast(nights: nights, then: a, else: b)
        }
    }

    private static func simplifyPercent(_ percent: Int, _ rule: Self) -> Self {
        switch (percent, rule) {
        case (0, let rule):
            return rule
        // Two discounts compose multiplicatively, NOT additively:
        // (1 - a)(1 - b) = 1 - (a + b - ab/100). Merge only if the result stays an Int.
        case let (a, .percentOff(b, inner)) where (a * b) % 100 == 0:
            return simplifyPercent(a + b - (a * b) / 100, inner)
        default:
            return .percentOff(percent, rule)
        }
    }

    private static func simplifyCombined(_ lhs: Self, _ rhs: Self) -> Self {
        switch (lhs, rhs) {
        case (.nightly(0), let rule), (let rule, .nightly(0)),
             (.cleaningFee(0), let rule), (let rule, .cleaningFee(0)):
            return rule
        default:
            return .combined(lhs, rhs)
        }
    }
}
