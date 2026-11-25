# Swift Testing: Theory and Snippets

Day 6, "tests as the agent's oracle". Reference: [Swift Testing](https://developer.apple.com/documentation/testing) and the [swift-testing repository](https://github.com/swiftlang/swift-testing). Written for Swift 6.4 / Xcode 27; exit tests and attachments need Swift 6.2 or later. Hands-on examples in this repo: `Tests/CombineSearchTests` (contract suite, deterministic clocks and schedulers), `Tests/ConcurrencyTests`, and ListingsKit in `ios-ai-agent-fundamentals/02-claude-code` (59 tests, 98% line coverage).

> **One sentence to memorize.** Swift Testing is macro-based: `@Test` marks a function, `#expect` / `#require` capture the *expression* so a failure prints both sides, tests run in parallel by default, and parameterized tests make each argument its own independent test case.

---

## 1. Why it matters for agents

An agent has no judgment about whether code is right. Its only reliable signal is a test result. Everything below serves one goal: **a test that fails, fails for the right reason, with a message that tells the reader what to change.**

| Property | Why an agent needs it |
|---|---|
| Failure message shows both sides (`#expect(a == b)` prints `a` and `b`) | The agent edits code from the message alone |
| One reason to fail per test, and a descriptive name | A red test name should say which requirement broke |
| Deterministic (no `sleep`, no wall-clock, no ordering luck) | A flaky test teaches the agent the wrong lesson and wastes retries |
| Fast | The agent runs them after every edit; xcfix and SwiftMigrator run them in a loop |
| `#require` for preconditions | Stops with one clear error instead of ten cascading ones |
| Tests that **fail** instead of **hang** | A hang gives the agent no message at all (see §10) |

---

## 2. The basics

```swift
import Testing
@testable import ListingsKit

@Test func formatsWholeDollars() {
    #expect(PriceFormatter.string(for: 120) == "$120")
}
```

- `@Test` marks a function. It can be a free function, or a method of a type (a suite). It can be `async`, `throws`, `@MainActor`.
- No naming convention (`testX`) is needed. Give a display name when the function name is not enough:

```swift
@Test("Prices below one dollar keep two decimals")
func smallPrice() { … }
```

- A test passes if it finishes without a recorded issue. A thrown error is a failure.

### `#expect` vs `#require`

```swift
@Test func decodesFirstListing() throws {
    let listings = try decode(fixture: "hotels.json")

    #expect(listings.count == 3)                           // records a failure, test CONTINUES
    let first = try #require(listings.first)               // failure STOPS the test; also unwraps the optional
    #expect(first.title == "Seaside Loft")
}
```

| | `#expect` | `#require` |
|---|---|---|
| On failure | Records an issue, **keeps running** | Throws, **stops this test** |
| Use for | The assertion you are testing | A precondition the rest of the test depends on |
| Optional unwrap | no | `try #require(optional)` returns the value (replaces `XCTUnwrap`) |

Failure messages show the evaluated sub-expressions:

```
Expectation failed: (first.title → "Beachfront Loft") == "Seaside Loft"
```

Add context when the expression alone isn't enough:

```swift
#expect(total == 450, "3 nights × 150, taxes excluded")
```

### Errors

```swift
#expect(throws: ListingError.notFound) { try service.listing(id: 0) }      // exact error value (Equatable)
#expect(throws: ListingError.self)     { try service.listing(id: 0) }      // any error of that type
#expect(throws: Never.self)            { try service.listing(id: 1) }      // must NOT throw

let error = #expect(throws: ListingError.self) { try service.listing(id: 0) }   // returns the error
#expect(error?.code == 404)

await #expect(throws: ListingError.notFound) { try await service.fetch(id: 0) } // async
```

For typed throws, the expected error type is checked the same way. `Issue.record("…")` reports a failure manually (replaces `XCTFail`).

---

## 3. Suites and test lifecycle

```swift
@Suite("Quote engine")
struct QuoteEngineTests {
    let engine: QuoteEngine                    // a FRESH instance of the suite per test

    init() { engine = QuoteEngine(rates: .fixture) }           // = setUp (can be async, throws)

    @Test func appliesWeekendRate() { … }
    @Test func appliesCleaningFee() { … }
    // deinit works as tearDown if the suite is a class/actor
}
```

- **Each test runs in a new instance of the suite type.** State is never shared between tests, which is the main correctness feature. Use `init` for setup and `deinit` (class or actor suites) for teardown.
- Suites can nest. A type containing `@Test` methods is a suite even without `@Suite`; add `@Suite` for a name or traits.
- A suite trait (`.tags`, `.serialized`, `.enabled`) applies to every test inside, recursively.

---

## 4. Parameterized tests

```swift
@Test("Currency formatting", arguments: [
    (cents: 0,      expected: "$0.00"),
    (cents: 5,      expected: "$0.05"),
    (cents: 12_345, expected: "$123.45"),
])
func formats(cents: Int, expected: String) {
    #expect(Money(cents: cents).formatted == expected)
}
```

- Each argument is a **separate test case** with its own result. One bad row fails alone and is named in the report, so an agent sees which input broke.
- Cases run **in parallel** and must be independent.
- Arguments must be `Sendable`.

Two collections: Swift Testing takes the **cartesian product** unless you `zip`:

```swift
@Test(arguments: [Locale(identifier: "en_US"), Locale(identifier: "es_AR")], [0, 5, 100])
func allCombinations(locale: Locale, cents: Int) { … }            // 2 × 3 = 6 cases

@Test(arguments: zip(["a", "b"], [1, 2]))
func paired(name: String, value: Int) { … }                       // 2 cases: ("a",1), ("b",2)
```

Readable names for cases: conform the argument to `CustomTestStringConvertible`:

```swift
enum Implementation: CaseIterable, CustomTestStringConvertible {
    case combine, asyncSequence
    var testDescription: String { self == .combine ? "combine" : "asyncSequence" }
}

@Test(arguments: Implementation.allCases)
func contract(_ implementation: Implementation) async { … }       // same test body, every implementation
```
That is the pattern used by `SearchContractTests`: one acceptance suite, run against both the Combine and the `AsyncSequence` pipeline.

Pitfall: an `arguments:` collection that is not a plain literal is evaluated when tests are **discovered**; keep it cheap and side-effect free.

---

## 5. Traits

Traits are passed to `@Test` or `@Suite` and change how a test is run or reported.

| Trait | Effect |
|---|---|
| `.tags(.network, .slow)` | Group tests (§6) |
| `.enabled(if: condition, "reason")` | Run only when true; otherwise reported as skipped |
| `.disabled("reason")` | Skipped, with a reason that shows in the report |
| `.bug("https://…/123", "flaky on CI")` | Links a test to a bug; shows in reports |
| `.timeLimit(.minutes(2))` | Fails the test if it runs longer. **Granularity is minutes** |
| `.serialized` | Run this suite's tests (and parameterized cases) one at a time |
| Custom `TestTrait` / `SuiteTrait` | Your own behavior (§7) |

```swift
@Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil, "needs a simulator"))
func usesRealKeychain() { … }

@Test(.bug("https://example.com/issues/42", "rounding differs on 32-bit"), .timeLimit(.minutes(1)))
func rounding() { … }

@Suite(.serialized)                       // shared fixture on disk: no parallelism inside this suite
struct DiskCacheTests { … }
```

Notes:
- `.serialized` only orders tests **within** that suite. Other suites still run in parallel with it.
- A test cannot use `.disabled` quietly: the reason is part of the report, which is what you want a reviewer (or agent) to read.
- `.timeLimit` is a guard rail, not a way to wait; design the test so it ends by itself.

---

## 6. Tags

Tags group tests across suites and files so a CI step or Xcode test plan can select them.

```swift
extension Tag {
    @Tag static var network: Self
    @Tag static var slow: Self
    @Tag static var regression: Self
}

@Suite(.tags(.network))
struct ExpediaServiceTests {
    @Test(.tags(.slow, .regression)) func recoversFromTimeout() async { … }
}
```

- Declare tags with `@Tag static var` in an `extension Tag`.
- Tags are inherited by every test in a tagged suite.
- Run by tag in Xcode (test plans, the Test navigator filter). From SwiftPM use `swift test --filter` / `--skip` with names.

---

## 7. Custom traits and scoped setup (`TestScoping`)

When setup is **around** the test body (a temporary directory, a task-local dependency, a mocked clock), a scoping trait runs the test inside your scope, which is safe under parallelism because it uses task-locals, not globals.

```swift
struct Environment {
    @TaskLocal static var clock: any Clock<Duration> = ContinuousClock()
}

struct ManualClockTrait: TestTrait, SuiteTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await Environment.$clock.withValue(ManualClock()) {       // the clock only inside this test
            try await function()
        }
    }
}

extension Trait where Self == ManualClockTrait {
    static var manualClock: Self { .init() }
}

@Test(.manualClock) func debounces() async { … }
```

Rule of thumb: `init` / `deinit` for per-instance setup, `TestScoping` for "set a task-local for the duration of the test".

---

## 8. Testing asynchronous code

```swift
@Test func loads() async throws {
    let listings = try await service.fetch(.init(city: "Lisbon"))
    #expect(listings.isEmpty == false)
}
```

### Events: `confirmation`

Replaces `XCTestExpectation` for "this callback or event happens N times":

```swift
@Test func notifiesOncePerChange() async {
    await confirmation("changed", expectedCount: 2) { changed in
        let token = model.onChange { changed() }                 // call the confirmation each time it happens
        model.set(1); model.set(2)
        _ = token
    }
}
// expectedCount: 0 asserts it NEVER happens. A range (1...3) is also accepted.
```
The confirmation must be fulfilled **before the closure returns**. For something that happens later, bridge it with a continuation or an `AsyncStream` and `await` it inside the closure.

### Deterministic time, never `sleep`

```swift
@Test func retriesWithBackoff() async throws {
    let clock = ManualClock()
    let task = Task { try await retrying(clock: clock) { try await flakyCall() } }

    await clock.waitForSleepers(1)             // the code is now waiting on the backoff
    clock.advance(by: .milliseconds(100))      // move time yourself
    #expect(try await task.value == .success)
}
```
Techniques used in this repo (see `Tests/CombineSearchTests`):
- **Inject the clock** (`Clock`) or scheduler (`Combine.Scheduler`); tests pass a manual one.
- **Controlled streams:** feed an `AsyncStream.Continuation` from the test and `await` outputs.
- **Gates and recorders** (`AsyncGate`, `OutputRecorder`) instead of delays: wait for an event, never for a duration.
- **Wait on the thing you assert**, not on a proxy: waiting for "someone is sleeping" can be satisfied by an old timer; count timers *started* instead.

### Actors and `@MainActor`

```swift
@MainActor
@Suite struct ViewModelTests {
    @Test func updatesTitle() async {
        let model = ListingViewModel(service: StubService())
        await model.load()
        #expect(model.title == "Seaside Loft")
    }
}
```
Isolate the test or suite to the actor of the code under test, so no `await MainActor.run` noise is needed.

### Known issues

```swift
withKnownIssue("rounding bug, tracked") {
    #expect(round(0.5) == 1)
}
// Reported as "expected failure". If the body STOPS failing, the test fails: the known issue is fixed, remove the wrapper.
// withKnownIssue(isIntermittent: true) tolerates a flaky failure.
```
Better than `.disabled` when you still want the code to run.

---

## 9. Exit tests and attachments (Swift 6.2+)

### Exit tests: code that must terminate the process

```swift
@Test func rejectsNegativeNights() async {
    await #expect(processExitsWith: .failure) {              // runs in a child process
        _ = Reservation(nights: -1)                          // precondition(nights >= 0) → process dies
    }
}

await #expect(processExitsWith: .exitCode(2)) { exit(2) }
```
- For `precondition`, `fatalError`, `exit`. The body runs in a **new process**, so it cannot capture local variables (pass values through the closure's capture list, which must be `Sendable & Codable`).
- Supported on macOS, Linux and Windows. **Not on iOS** simulators/devices.

### Attachments

```swift
@Test func rendersInvoice() throws {
    let output = try render(invoice)
    Attachment.record(output.pdfData, named: "invoice.pdf")   // saved with the test result
    #expect(output.pageCount == 1)
}
```
Attach whatever a reader needs to diagnose a failure: the request body, the decoded JSON, an image, a log. Your own types can conform to `Attachable`.

---

## 10. Failing correctly: tests an agent can use

1. **Name the requirement, not the method.** `@Test("A stale response is never emitted")` beats `testSearch3`.
2. **One behavior per test**, so the failing name says which one.
3. **Assert on values, not on `true`.** `#expect(a == b)` prints both sides; `#expect(isValid)` prints only `false`. Write `#expect(result == .valid)`.
4. **Use `#require` for preconditions**, so the failure points at the cause (`first` was `nil`), not at three later lines.
5. **Prefer failing over hanging.** A test that waits for an event that never comes just hangs and gives no message. Make the wait bounded by design (resume continuations on cancel, finish streams) and add `.timeLimit(.minutes(1))` as a net. In this repo a missing `receiveCancel` hook made an acceptance test hang instead of fail; a stricter harness would have reported it.
6. **Never `sleep`.** Real time makes tests slow and non-deterministic; flakiness teaches an agent to retry instead of fix.
7. **Run concurrency tests many times.** `for i in $(seq 10); do swift test; done`. One green run proves little for races.
8. **Stable ordering of results.** Sort or use `Set`/dictionary comparison when order is not part of the contract.
9. **Avoid shared mutable state** between tests (parallel by default): fresh suite instance, injected dependencies.
10. **Test the contract, not the implementation**, so an agent can rewrite internals and still be judged by the same oracle (the Combine ↔ `AsyncSequence` contract suite is exactly this).

---

## 11. Test doubles

| Double | What it does | Example |
|---|---|---|
| Stub | Returns canned answers | `StubTransport` returns a fixture for any request |
| Fake | A working, simpler implementation | An in-memory repository |
| Spy | Records calls so you can assert on them | A service that appends each query to `queries` |
| Mock | Pre-programmed with expectations that verify themselves | Rare in Swift; prefer spy + `#expect` |

```swift
protocol Transport: Sendable { func data(for request: URLRequest) async throws -> (Data, URLResponse) }

actor SpyTransport: Transport {
    private(set) var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Test func sendsLocaleHeader() async throws {
    let spy = SpyTransport()
    _ = try await ExpediaService(transport: spy).fetch(.init(city: "Lisbon"))
    #expect(await spy.requests.first?.value(forHTTPHeaderField: "Accept-Language") == "en-US")
}
```

When to mock: at **boundaries you don't own** (network, clock, disk, randomness, system services). When not to: your own pure logic and value types; use the real thing. Over-mocking couples tests to implementation, which is what makes a refactor by an agent look like a failure.

Technique that scales: protocol with a `Sendable` constraint, injected through the initializer, with a **live**, a **test** and a **preview** implementation.

For `URLSession`-based code, a `URLProtocol` stub tests the real client end to end without a network.

---

## 12. Coverage

```bash
swift test --enable-code-coverage
swift test --show-codecov-path                 # path to the JSON report
xcrun llvm-cov report .build/…/YourPackagePackageTests.xctest/Contents/MacOS/YourPackagePackageTests \
    -instr-profile .build/…/codecov/default.profdata -ignore-filename-regex='Tests|\.build'
```
In Xcode: enable "Gather coverage" in the scheme's Test options, or `xcodebuild test -enableCodeCoverage YES -resultBundlePath out.xcresult`, then `xcrun xccov view --report out.xcresult`.

- Line coverage says what ran, not what was **asserted**. A high number with weak `#expect`s is a false comfort; read the uncovered lines (error paths, `default` cases, decoding failures) first.
- Target the logic, not the glue: transport/`URLSession` wrappers are usually the 0% line, and that is acceptable if they are thin and covered by an integration test.
- Useful gate for an agent: "coverage does not go down" plus "every acceptance criterion maps to a test".

---

## 13. Coexisting with XCTest and migrating

Both frameworks can live in the same test target. **They don't mix assertions**: `#expect` is for Swift Testing functions, `XCTAssert*` for `XCTestCase`.

| XCTest | Swift Testing |
|---|---|
| `class FooTests: XCTestCase` | `struct FooTests` (or `@Suite`) |
| `func testBar()` | `@Test func bar()` |
| `setUp()` / `tearDown()` | `init()` / `deinit` (class or actor suite) |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertTrue(x)` | `#expect(x)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTUnwrap(x)` | `try #require(x)` |
| `XCTAssertThrowsError(try f())` | `#expect(throws: SomeError.self) { try f() }` |
| `XCTFail("…")` | `Issue.record("…")` |
| `XCTSkip` / `XCTSkipIf` | `.enabled(if:)` / `.disabled` traits |
| `XCTestExpectation` + `wait(for:)` | `confirmation { … }` or plain `async` + `await` |
| `XCTExpectFailure` | `withKnownIssue` |
| Looping over inputs | `@Test(arguments:)` |
| `measure { }` | **Not supported**: keep XCTest (or a benchmark target) |
| `XCUIApplication` UI tests | **Not supported**: keep XCTest |

Migration steps, in order (what a SwiftMigrator rule would say):
1. Convert one file at a time; the module keeps building because both frameworks coexist.
2. Keep every assertion: **never drop a check to make the test compile**.
3. Replace `wait(for:)` expectations by `async` tests or `confirmation`; do not leave `sleep`.
4. Turn loops and copy-pasted tests into `arguments:`.
5. Run the **before** and **after** suites and compare the number of cases and the same bugs they catch (mutation check: break the code, both versions must fail).

Not migrated: UI tests, performance tests, Objective-C tests, tests that rely on `XCTestCase` subclass hooks.

---

## 14. Running and CI

```bash
swift test                                     # everything, parallel
swift test --filter ListingsKitTests           # by suite or test name
swift test --skip Slow                         # exclude
swift test --no-parallel                       # debug ordering problems
swift test --enable-code-coverage
```
```bash
xcodebuild test -scheme ListingsKit -destination 'platform=iOS Simulator,name=iPhone 16' \
    -enableCodeCoverage YES -resultBundlePath out.xcresult | xcbeautify
```
- Tests in a suite and cases of a parameterized test run **in parallel**: any shared state is a bug.
- Test order is not guaranteed; do not depend on it.
- `.serialized` for the rare shared resource; prefer to remove the sharing.
- Concurrency tests: repeat the run (10×) in CI before trusting them.

---

## 15. Pitfalls checklist

1. `#expect(x)` for a Bool loses information; compare to a value.
2. Forgetting `try`/`await` inside `#expect`: the macro accepts it but the closure form (`#expect(throws:)`) needs `await` outside.
3. Tests that share a global, a file or a singleton fail only in parallel.
4. `sleep` or `Task.sleep` to "wait for it": use a clock, a gate or an event.
5. A `confirmation` fulfilled after its closure returned is a failure.
6. `#expect` after a failed unwrap: use `#require` so one cause gives one error.
7. Expecting order from a `Set` or `Dictionary`.
8. Cartesian product by accident: two `arguments:` collections are multiplied; `zip` for pairs.
9. `.timeLimit` is in minutes; it is not a performance assertion.
10. `.serialized` does not stop other suites from running in parallel with the serialized one.
11. Exit tests do not run on iOS; guard with `.enabled(if:)` or keep them in a macOS/Linux target.
12. A test that hangs gives no message; make waits bounded and add a time limit.
13. High coverage with no assertions: review the uncovered *and* the asserted lines.

---

## 16. Questions and Answers

**1. Why Swift Testing over XCTest for new code?**
It uses plain Swift (structs, `async`, macros) instead of a class hierarchy with `test`-prefixed methods. `#expect` captures the expression, so the failure shows both sides without a family of `XCTAssert*` functions. Parameterized tests make each input its own reported case. Tests run in parallel by default and each gets a fresh suite instance, which removes shared-state bugs. It also gives traits, tags, `confirmation`, exit tests and attachments. XCTest remains for UI tests, performance (`measure`) and Objective-C.

**2. `#expect` vs `#require`?**
`#expect` records a failure and the test continues, so one run reports several problems. `#require` throws and stops the test; use it for preconditions that later lines depend on, and to unwrap optionals (`try #require(list.first)`). Rule: assert the behavior with `#expect`, guard the setup with `#require`.

**3. How does a parameterized test help find bugs faster?**
Each argument is an independent test case with its own pass/fail and its name in the report, and they run in parallel. A failure points at the exact input, not at a loop iteration. Two collections form a cartesian product unless you `zip` them. Arguments must be `Sendable`, and `CustomTestStringConvertible` gives readable case names.

**4. A test is flaky only on CI. How do you investigate?**
Look for what differs: parallelism, real time, ordering, shared state. Run it many times with `--no-parallel` to see whether it is a shared-state bug, then replace real time with an injected clock or scheduler, replace `sleep` with an event or gate, and sort unordered results. For concurrency I run the suite ten times in a row before trusting it. Mark a genuinely unfixable one with `.bug(…)` and `withKnownIssue(isIntermittent: true)` rather than deleting or silently disabling it.

**5. How do you test code with `debounce` or retry-with-backoff without waiting?**
Inject the time source: a `Clock` for async code, a `Scheduler` for Combine. Tests pass a manual one whose time moves only on `advance(by:)`. Start the code under test, wait until its timer exists (a counting clock or a "sleepers" waiter, not an old timer), advance time, and then await the output. The assertion that nothing happened early is "advance by 299 ms and nothing has been emitted".

**6. What replaces `XCTestExpectation`?**
For an event that occurs N times, `await confirmation(expectedCount:) { confirm in … }`; it must be fulfilled before the closure returns. For async results, simply `await` them in an `async` test. For callbacks, bridge them with `withCheckedContinuation` or an `AsyncStream` and await that, instead of waiting with a timeout.

**7. When do you use a custom trait with `TestScoping`?**
When setup must wrap the test body, such as installing a manual clock, a mock environment or a temporary directory, and it must be safe under parallel execution. The trait sets a `@TaskLocal` for the duration of `provideScope(for:testCase:performing:)`, so concurrently running tests don't see each other's values. For plain per-test setup, `init`/`deinit` of the suite is enough.

**8. What are tags and how do they differ from suites?**
Suites group tests by **structure** (a type); tags group by **concern** across files and suites (`.network`, `.slow`, `.regression`). You declare them with `@Tag` in an `extension Tag`, apply with `.tags(...)`, and select them in Xcode test plans or the Test navigator, for example to run only fast tests on every commit and the slow ones nightly.

**9. How would you test code that calls `fatalError` or `precondition`?**
With an exit test: `await #expect(processExitsWith: .failure) { … }` (Swift 6.2+). The body runs in a child process, so the parent test survives and checks the exit status. It cannot capture local state freely, and it is not available on iOS, so I keep those tests in a macOS or Linux target.

**10. How do you migrate an XCTest suite safely?**
One file at a time, because both frameworks coexist in a target. Map `setUp` to `init`, `XCTAssertEqual` to `#expect(a == b)`, `XCTUnwrap` to `#require`, `XCTFail` to `Issue.record`, expectations to `confirmation` or `async`, loops to `arguments:`. Never drop an assertion to make it compile. Verify equivalence: same number of cases, and a mutation check (break the code and confirm the old and new suites both fail). UI and performance tests stay in XCTest.

**11. Coverage is 98%. Is the code well tested?**
Not necessarily. Line coverage shows what executed, not what was asserted. I read the uncovered lines first (error paths, `default` branches, decode failures, the transport glue) and then sample tests for weak assertions. A better quality gate is that every acceptance criterion maps to a test, plus a mutation-style check. The uncovered thin wrapper over `URLSession` is usually fine; an uncovered error branch is not.

**12. Why do you say "tests are the agent's oracle", and what do you do about it?**
An agent can't judge correctness; the test result is its only dependable signal. So the tests must be deterministic (no real time or ordering luck), specific (one behavior per test, named after the requirement), explicit in failures (`#expect(a == b)` with both sides, `#require` for preconditions) and bounded (fail instead of hang). I write them before the agent starts, from numbered acceptance criteria, and a stop hook runs build and tests so the agent can't finish on red. I never let an agent edit or delete a test to get green; that is a forbidden action in my migration playbook.

**13. What did you learn from a test that hung?**
In the Combine search exercise, removing the hook that cancels the underlying `Task` made the "superseded search is cancelled" test wait forever instead of failing, and another bridge test starved the main actor with a yield loop. A hang gives the agent no message. The fixes: make waits bounded by construction (finish streams, resume continuations on cancel), add `.timeLimit` as a safety net, and keep a pair of acceptance tests (stale value ignored, work cancelled) because they fail for different reasons.

**14. When do you mock and when don't you?**
Mock at boundaries you don't control: network, clock, disk, randomness, system services. Use real objects for your own pure logic and value types. Prefer a hand-written stub, fake or spy behind a small `Sendable` protocol injected through the initializer, with live, test and preview implementations. Over-mocking couples the tests to implementation details, so a harmless refactor (by me or by an agent) turns the suite red.
