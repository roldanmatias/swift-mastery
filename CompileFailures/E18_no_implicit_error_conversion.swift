// expect: cannot be converted
enum ListingError: Error { case bad }
enum BookingError: Error { case listing(ListingError) }
func validate() throws(ListingError) {}
func book() throws(BookingError) { try validate() }
