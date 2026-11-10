// Ex 07 — `inout` and the Law of Exclusivity.
//
// `inout` is semantically copy-in/copy-out: the callee gets its own variable,
// and the result is written back when the call returns. While the call runs,
// the caller's variable is under an exclusive "modify" access: nothing else may
// read or write it.

import Foundation

enum E07 {
    static func applyDiscount(_ price: inout Decimal, percent: Int) {
        price = price * Decimal(100 - percent) / 100
    }

    struct Listing {
        var nightlyPrice: Decimal {
            didSet { didSetCount += 1 }
        }
        private(set) var didSetCount = 0

        init(nightlyPrice: Decimal) {
            self.nightlyPrice = nightlyPrice
        }
    }

    /// Mutates its argument three times.
    static func bumpThreeTimes(_ value: inout Decimal) {
        value += 1
        value += 1
        value += 1
    }

    // Step 3 — compile-time overlapping accesses (static enforcement):
    //
    //   func transfer(_ a: inout Int, _ b: inout Int) { … }
    //   var x = 10
    //   transfer(&x, &x)
    //   // error: inout arguments are not allowed to alias each other
    //
    //   swap(&nights[0], &nights[1])
    //   // error: overlapping accesses to 'nights', but modification requires exclusive access;
    //   //        consider calling MutableCollection.swapAt(_:_:) [#ExclusivityViolation]
    //
    // `nights.swapAt(0, 1)` is fine: it is ONE mutating access to the array,
    // and the method swaps internally.

    // Step 4 — compiles, traps at runtime (dynamic enforcement). Class
    // properties, globals and escaping-closure captures can't be proven
    // exclusive at compile time, so the runtime tracks the accesses.
    final class Counter {
        var value = 0
    }

    static func modify(_ value: inout Int, then body: () -> Void) {
        value += 1
        body()
    }

    /// Crashes with "Simultaneous accesses to …, but modification requires exclusive access".
    static func triggerExclusivityViolation() {
        let counter = Counter()
        modify(&counter.value) {
            counter.value += 1   // second modify access while the first one is still active
        }
    }

    // Step 5 — two different stored properties of a *local* struct can be
    // accessed at the same time: the compiler can prove they don't overlap.
    struct Stay {
        var nights = 1
        var guests = 1
    }

    static func balance(_ a: inout Int, _ b: inout Int) {
        let total = a + b
        a = total / 2
        b = total - a
    }

    static func balanceLocalStay() -> Stay {
        var stay = Stay()
        stay.nights = 5
        balance(&stay.nights, &stay.guests)   // OK for a local var
        return stay
    }
    // Not OK for a global `var stay`, or for `stay` as a stored property of a
    // class: there the compiler treats the whole struct as one access.
}
