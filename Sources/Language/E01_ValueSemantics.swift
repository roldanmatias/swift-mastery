// Ex 01 — Value vs reference semantics.
//
// Value semantics = mutating one variable can never be observed through another
// variable. It is a property of the type's *behavior*: a struct only has value
// semantics if all of its stored properties do.

import Foundation

enum E01 {
    // MARK: Step 1 — the inherited (broken) design

    final class PhotoGalleryRef {
        var urls: [URL] = []
    }

    /// A struct, but NOT a value type: copies share the gallery object.
    struct BrokenListing {
        var title: String
        var nightlyPrice: Decimal
        var gallery: PhotoGalleryRef

    }

    // MARK: Step 2 — value semantics by construction

    /// `PhotoGallery` becomes a struct holding `[URL]` (itself a CoW value type).
    /// The call site `listing.gallery.urls.append(x)` still compiles unchanged.
    struct PhotoGallery: Equatable, Sendable {
        var urls: [URL] = []
    }

    // MARK: Step 3 — a type where identity *is* the semantics

    /// Two hosts with the same name are different people, so `Host` is a class.
    /// Sharing one `Host` between listings is correct: renaming the host must be
    /// visible from every listing they own.
    final class Host {
        let id = UUID()
        var name: String
        init(name: String) { self.name = name }
    }

    struct Listing {
        var title: String
        var nightlyPrice: Decimal
        var gallery = PhotoGallery()
        /// Deliberately shared reference: identity, not a value.
        var host: Host

    }
}
