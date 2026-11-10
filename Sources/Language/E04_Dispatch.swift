// Ex 04 — Extensions and method dispatch.
//
// Three dispatch mechanisms:
// - static (direct call): non-requirement protocol-extension members, structs,
//   `final` / `private` members, extension members of classes
// - witness table: protocol requirements called through a generic or `any`
// - vtable: overridable class methods

protocol E04Describable {
    func summary() -> String           // requirement → witness-table entry
}

extension E04Describable {
    func summary() -> String { "generic summary" }
    func badge() -> String { "generic badge" }   // NOT a requirement → static
}

enum E04 {
    struct Listing: E04Describable {
        func summary() -> String { "listing summary" }
        func badge() -> String { "listing badge" }
    }

    // MARK: The trap

    /// Conforms using the protocol extension's default `summary()`.
    /// The witness table for `BaseCard: E04Describable` is built *here*, and it
    /// points at the default implementation.
    class BaseCard: E04Describable {
    }

    /// This is NOT an override (there's nothing in `BaseCard`'s vtable to
    /// override). It only shadows the extension method for static calls on
    /// `PremiumCard`. Generic/existential calls go through `BaseCard`'s witness
    /// table and still print "generic summary".
    final class PremiumCard: BaseCard {
        func summary() -> String { "premium summary" }
    }

    // MARK: Fix 1 — put the requirement in the class so it gets a vtable slot

    class FixedBaseCard: E04Describable {
        func summary() -> String { "base summary" }
    }

    final class FixedPremiumCard: FixedBaseCard {
        override func summary() -> String { "premium summary" }
    }

    // MARK: Fix 2 — composition instead of inheritance

    struct ComposedPremiumCard: E04Describable {
        let base = BaseCard()
        func summary() -> String { "premium summary" }
    }

    // MARK: Call-site helpers used by the tests

    static func viaGeneric<T: E04Describable>(_ value: T) -> (summary: String, badge: String) {
        (value.summary(), value.badge())
    }

    static func viaExistential(_ value: any E04Describable) -> (summary: String, badge: String) {
        (value.summary(), value.badge())
    }
}
