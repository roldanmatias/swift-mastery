// expect: escape
func run(_ body: @escaping () -> Void) {}
func f(_ prices: [Double]) { let span = prices.span; run { _ = span.count } }
