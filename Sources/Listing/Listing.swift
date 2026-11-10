// Ex 05 — a module that contains a type with the same name as the module.
// Before module selectors, `Listing.Listing` could not be written from a module
// that also had something named `Listing` in scope: the first `Listing` resolves
// to the *type*, not the module. `Listing::Listing` fixes that.

package struct Listing: Sendable, Equatable {
    package var title: String

    package init(title: String) {
        self.title = title
    }
}
