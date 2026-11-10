// Ex 05 — Module selectors `Module::Name` (SE-0491, Swift 6.3+).
//
// `Payments` and `Pricing` both declare `Money` and `String.slug`. The `Listing`
// module contains a type called `Listing`. And this module (`Language`) also has
// a top-level `Listing` (Domain.swift) and a top-level `Money` (below).

import Foundation
import Listing
import Payments
import Pricing

/// `Language`'s own top-level `Money`. Because it's declared in the current
/// module, it shadows both imported `Money` types for unqualified lookups.
struct Money: Sendable, Equatable {
    var label: String
}

enum E05 {
    // Step 1 — pick a declaration from a specific module.
    static func convert(_ money: Payments::Money) -> Pricing::Money {
        Pricing::Money(amount: Decimal(money.cents) / 100)
    }

    // Step 2 — a module selector on a *member*: picks which module's extension
    // member to call on the same value.
    //
    // ⚠️ Observed on Swift 6.3.2 and 6.4.2: this compiles, but BOTH calls run
    // the same extension (`Payments`' here). Selectors on top-level names
    // (`Payments::Money`) and on nested types (`Ship.A::Engine`) work. It looks
    // like a compiler bug; the test documents it with `withKnownIssue`.
    static func slugs(for name: String) -> (payments: String, pricing: String) {
        (name.Payments::slug, name.Pricing::slug)
    }

    // Step 3 — shadowing inside a nested scope.
    struct Checkout {
        struct Money: Equatable {
            var nested = true
        }

        /// Unqualified `Money` here means `Checkout.Money` (innermost scope).
        func nestedMoney() -> Money { Money() }

        /// `Language::Money` starts the lookup at the top level of `Language`,
        /// skipping `Checkout.Money`.
        func topLevelMoney() -> Language::Money { Language::Money(label: "top-level") }
    }

    // Step 4 — the module/type name clash.
    //
    // Before SE-0491:  `Listing.Listing` → the first `Listing` resolves to a
    // *type* (`Language.Listing`, since the current module wins), and that type
    // has no member called `Listing`:
    //
    //   let x: Listing.Listing   // error: 'Listing' is not a member type of struct 'Language.Listing'
    //
    // With a module selector, `Listing::` names the module unambiguously:
    static func importedListing(title: String) -> Listing::Listing {
        Listing::Listing(title: title)
    }

    static func localListing(title: String) -> Language::Listing {
        Language::Listing(title: title, nightlyPrice: 100)
    }

    // Step 5 — selectors can't be used on *new* declarations:
    //
    //   struct Payments::Refund {}
    //   // error: expected '{' in struct      (Swift 6.4.2: a plain parse error)
    //
    // New declarations always belong to the current module, so a selector there
    // would either be redundant or a lie.
}
