// Shared booking domain used by several exercises and by the StayKit capstone.
// Exercise-specific variants live inside each exercise's namespace (`E01`, `E02`, …),
// so the same names can be redefined per exercise without collisions.

import Foundation

package typealias ListingID = Tagged<Listing, UUID>
package typealias HostID = Tagged<Host, UUID>

/// A bookable listing. Pure value type: every stored property has value semantics.
package struct Listing: Identifiable, Hashable, Sendable {
    package let id: ListingID
    package var title: String
    package var city: String
    package var nightlyPrice: Decimal
    package var rating: Double
    package var maxGuests: Int
    package var amenities: Set<String>
    package var petsAllowed: Bool

    package init(
        id: ListingID = ListingID(UUID()),
        title: String,
        city: String = "Buenos Aires",
        nightlyPrice: Decimal,
        rating: Double = 4.5,
        maxGuests: Int = 4,
        amenities: Set<String> = [],
        petsAllowed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.city = city
        self.nightlyPrice = nightlyPrice
        self.rating = rating
        self.maxGuests = maxGuests
        self.amenities = amenities
        self.petsAllowed = petsAllowed
    }
}

package struct Host: Identifiable, Hashable, Sendable {
    package let id: HostID
    package var name: String

    package init(id: HostID = HostID(UUID()), name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Error domain (Ex 17, 18, capstone)

package enum ListingError: Error, Hashable, Sendable {
    case notFound(ListingID)
    case invalidPrice(Decimal)
    case unavailable(Range<Date>)
}

package enum PaymentError: Error, Hashable, Sendable {
    case declined
    case fraudSuspected
}

package enum BookingError: Error, Hashable, Sendable {
    case listing(ListingError)
    case payment(PaymentError)
    case lockUnavailable(ListingID)
    case invalidRequest([String])
}
