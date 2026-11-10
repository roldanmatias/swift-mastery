// Ex 29 — `InlineArray` and `Span`: the hot-path rewrite.
//
// `InlineArray<N, T>` (`[N of T]`): N elements stored inline, no heap, no CoW,
// no refcount. Copying it copies all N elements (eager).
// `Span<T>`: a non-owning, bounds-checked, `~Escapable` view of contiguous
// memory. It can't outlive the storage it borrows from.

package enum E29 {
    package static let windowSize = 7

    /// Baseline: a fresh heap-allocated `[Double]` window for every step
    /// (1 allocation + growth reallocations per output value).
    package static func weeklyAveragesBaseline(_ prices: [Double]) -> [Double] {
        guard prices.count >= windowSize else { return [] }
        var averages: [Double] = []
        averages.reserveCapacity(prices.count - windowSize + 1)
        for start in 0...(prices.count - windowSize) {
            var window: [Double] = []
            for offset in 0..<windowSize {
                window.append(prices[start + offset])
            }
            averages.append(averageOfArray(window))
        }
        return averages
    }

    /// Fair baseline: ONE heap array reused for every window
    /// (`removeAll(keepingCapacity:)`), so it measures Array vs InlineArray,
    /// not "allocate per step" vs "don't".
    package static func weeklyAveragesReusedArray(_ prices: [Double]) -> [Double] {
        guard prices.count >= windowSize else { return [] }
        var averages: [Double] = []
        averages.reserveCapacity(prices.count - windowSize + 1)
        var window: [Double] = []
        window.reserveCapacity(windowSize)
        for start in 0...(prices.count - windowSize) {
            window.removeAll(keepingCapacity: true)
            for offset in 0..<windowSize {
                window.append(prices[start + offset])
            }
            averages.append(average(window.span))
        }
        return averages
    }

    package static func averageOfArray(_ window: [Double]) -> Double {
        var sum = 0.0
        for value in window { sum += value }
        return sum / Double(window.count)
    }

    /// Storage-agnostic: works for `Array`, `InlineArray`, `UniqueArray`,
    /// `ContiguousArray`, a `Data` region… anything that can vend a `Span`.
    package static func average(_ window: Span<Double>) -> Double {
        var sum = 0.0
        for index in window.indices { sum += window[index] }
        return sum / Double(window.count)
    }

    /// Rewrite: the window is a stack-allocated `[7 of Double]`, reused across
    /// iterations and read through its `span`. Zero allocations in the loop.
    package static func weeklyAveragesInline(_ prices: [Double]) -> [Double] {
        guard prices.count >= windowSize else { return [] }
        var averages: [Double] = []
        averages.reserveCapacity(prices.count - windowSize + 1)
        var window: [7 of Double] = .init(repeating: 0)
        for start in 0...(prices.count - windowSize) {
            for offset in 0..<windowSize {
                window[offset] = prices[start + offset]
            }
            averages.append(average(window.span))
        }
        return averages
    }

    /// In-place normalization through a `MutableSpan`: exclusive, bounds-checked
    /// access without exposing an unsafe pointer.
    package static func normalize(_ prices: inout [Double]) {
        guard let maximum = prices.max(), maximum > 0 else { return }
        var span = prices.mutableSpan
        for index in span.indices {
            span[index] /= maximum
        }
    }

    // Step 4 — lifetime errors (Swift 6.4.2):
    //
    //   func makeSpan() -> Span<Double> { let a = [1.0, 2.0]; return a.span }
    //   // error: a function cannot return a ~Escapable result
    //
    //   final class Cache { var window: Span<Double> }
    //   // error: the 'get' accessor cannot return a ~Escapable result
    //
    //   let span = prices.span
    //   DispatchQueue.main.async { print(span.count) }
    //   // error: lifetime-dependent variable 'span' escapes its scope
    //
    // Step 5 — semantics:
    //   for x in window { }
    //   // Swift 6.4.2, macOS 26: error: for-in loop requires '[7 of Double]' to conform to
    //   //   'Iterable', which is only available in macOS 27.0 or newer
    //   InlineArray is NOT a Sequence/Collection. With SE-0516 it conforms to `Iterable`
    //   (borrowing iteration) on macOS 27+; before that, iterate `indices` or its `span`.
}
