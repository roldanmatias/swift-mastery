// Ex 29–30 benchmarks. Run in release mode:
//
//     swift run -c release OwnershipBenchmarks
//
// Method: warm-up run, then N timed runs with `ContinuousClock`; report median and
// p90. Results feed a `blackHole` so the optimizer can't delete the work.
// Allocation counts: use Instruments → Allocations (or ordo-one/package-benchmark's
// `mallocCountTotal` metric); this harness only measures time.

import Ownership

@inline(never)
func blackHole<T>(_ value: T) {
    withExtendedLifetime(value) {}
}

struct Stats {
    let median: Duration
    let p90: Duration

    init(_ samples: [Duration]) {
        let sorted = samples.sorted()
        median = sorted[sorted.count / 2]
        p90 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
    }
}

func measure(runs: Int = 15, _ body: () -> Void) -> Stats {
    body()   // warm-up
    let clock = ContinuousClock()
    return Stats((0..<runs).map { _ in clock.measure(body) })
}

func format(_ duration: Duration) -> String {
    let ms = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    return String(format: "%9.2f ms", ms)
}

func report(_ name: String, _ stats: Stats, baseline: Stats? = nil) {
    var line = "\(name.padding(toLength: 34, withPad: " ", startingAt: 0)) median \(format(stats.median))   p90 \(format(stats.p90))"
    if let baseline {
        let ratio = Double(baseline.median.components.attoseconds + baseline.median.components.seconds * 1_000_000_000_000_000_000)
            / Double(stats.median.components.attoseconds + stats.median.components.seconds * 1_000_000_000_000_000_000)
        line += String(format: "   %.1f× faster", ratio)
    }
    print(line)
}

// MARK: Ex 29 — weekly averages: [Double] window vs InlineArray + Span

// Explicit closure types: Swift 6.3 times out type-checking the unannotated version.
let prices: [Double] = (0..<365).map { (day: Int) -> Double in
    let weekday = Double(day % 7)
    let monthDay = Double(day % 30)
    return 80 + weekday * 10 + monthDay
}
let iterations = 2_000   // 2,000 × 359 windows ≈ 718k windows per run

print("Ex 29 — 7-night rolling average, \(iterations) × 365 days")
let baseline = measure {
    for _ in 0..<iterations { blackHole(E29.weeklyAveragesBaseline(prices)) }
}
let reused = measure {
    for _ in 0..<iterations { blackHole(E29.weeklyAveragesReusedArray(prices)) }
}
let inline = measure {
    for _ in 0..<iterations { blackHole(E29.weeklyAveragesInline(prices)) }
}
report("Array window per step (naive)", baseline)
report("One reused Array + Span", reused, baseline: baseline)
report("InlineArray + Span", inline, baseline: baseline)
report("InlineArray vs reused Array", inline, baseline: reused)

// MARK: Ex 30 — UniqueArray vs Array (needs macOS 27 at runtime)

#if compiler(>=6.4)
if #available(macOS 27, iOS 27, *) {
    let count = 10_000_000
    print("\nEx 30 — \(count) appends + in-place updates")
    let array = measure(runs: 7) {
        var values: [Int] = []
        for i in 0..<count { values.append(i) }
        for i in 0..<count { values[i] &+= 1 }
        blackHole(values.count)
    }
    let unique = measure(runs: 7) {
        var values = UniqueArray<Int>()
        for i in 0..<count { values.append(i) }
        for i in 0..<count { values[i] &+= 1 }
        blackHole(values.count)
    }
    report("Array<Int>", array)
    report("UniqueArray<Int>", unique, baseline: array)
} else {
    print("\nEx 30 — skipped: UniqueArray requires macOS 27 at runtime (this is macOS 26).")
}
#endif
