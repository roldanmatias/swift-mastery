// expect: cannot convert value of type
struct Tagged<Tag, Raw> { let raw: Raw }
enum ListingTag {}; enum HostTag {}
func host(_ id: Tagged<HostTag, Int>) {}
func f() { host(Tagged<ListingTag, Int>(raw: 1)) }
