// StayKit — C6: pricing. A `PricingRule` tree (Ex 02) for fees/discounts, plus
// an `InlineArray` weekday table and a `Span` hot path (Ex 29).

import Foundation
import Language
import Ownership

struct QuoteEngine: Sendable {
    /// Fixed-size lookup table, Mon…Sun: stored inline, no heap, no CoW.
    /// Defaults on the properties give the memberwise init the same defaults:
    /// `QuoteEngine()`, `QuoteEngine(cleaningFee: 50)`, … (internal type, so no
    /// hand-written init needed).
    var weekdayMultipliers: [7 of Double] = [1, 1, 1, 1, 1.2, 1.25, 1.1]
    var cleaningFee: Decimal = 30
    var weeklyDiscountPercent: Int = 10

    /// Exact money math in `Decimal`; `Double` only for the display average.
    func quote(
        for listing: Listing,
        calendar: AvailabilityCalendar,
        nights: Range<Int>,
        guests: Int
    ) -> Quote {
        var nightlyDecimal: Decimal = 0
        var nightly: [Double] = []
        nightly.reserveCapacity(nights.count)
        for day in nights {
            let multiplier = weekdayMultipliers[day % 7]
            let price = calendar[day].price * Decimal(multiplier)
            nightlyDecimal += price
            nightly.append(multiplier * NSDecimalNumber(decimal: calendar[day].price).doubleValue)
        }
        let averageNightlyDecimal = nightlyDecimal / Decimal(nights.count)

        let rule = E02.PricingRule.combined(
            .ifStayAtLeast(
                nights: 7,
                then: .percentOff(weeklyDiscountPercent, .nightly(averageNightlyDecimal)),
                else: .nightly(averageNightlyDecimal)
            ),
            .cleaningFee(cleaningFee)
        ).simplified()

        var total = rule.total(nights: nights.count)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &total, 2, .bankers)

        return Quote(
            listingID: listing.id,
            nights: nights,
            guests: guests,
            total: rounded,
            averageNightly: E29.average(nightly.span)
        )
    }
}
