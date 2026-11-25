# Combine: Interview Theory

Reference: [Combine documentation](https://developer.apple.com/documentation/combine). The sections follow its structure: publishers, subscribers, subjects, operators, errors, schedulers, sharing, Foundation integration and the Swift concurrency bridge. Hands-on companion: [swift-6.4-combine-exercises.md](swift-6.4-combine-exercises.md) (`Sources/Combine`, `Tests/CombineSearchTests`).

> **One sentence to memorize.** Combine is a declarative framework for processing values over time: a `Publisher` emits values to a `Subscriber`, with operators in between, and the subscriber controls how much it receives (demand).

Availability: iOS 13 / macOS 10.15 and later. Combine is not deprecated, but Apple's new APIs (`@Observable`, `Observations`, `AsyncSequence`) favor Swift concurrency. Know Combine for the codebases you will inherit, and know when you would **not** write new Combine.

---

## 1. The model: three roles and a handshake

| Role | Type | Job |
|---|---|---|
| Publisher | `Publisher` (`Output`, `Failure`) | Describes a sequence of values over time. **A value type recipe; nothing happens until someone subscribes** |
| Subscriber | `Subscriber` (`Input`, `Failure`) | Receives values and a completion. Requests values through *demand* |
| Subscription | `Subscription` | The live connection. Created by the publisher, handed to the subscriber, used to request demand and to cancel |

The handshake, in order:

1. `publisher.subscribe(subscriber)` (or `receive(subscriber:)` under the hood).
2. The publisher creates a `Subscription` and calls `subscriber.receive(subscription:)`.
3. The subscriber calls `subscription.request(_ demand: Subscribers.Demand)`.
4. The publisher calls `receive(_ input:)` for each value, up to the demand. The subscriber's return value adds demand.
5. The stream ends with exactly one `receive(completion:)` (`.finished` or `.failure`), or the subscriber cancels.

```swift
import Combine

let publisher = [1, 2, 3].publisher            // Publishers.Sequence<[Int], Never>
let cancellable = publisher.sink(
    receiveCompletion: { print("completion:", $0) },   // .finished
    receiveValue: { print("value:", $0) }              // 1 2 3
)
```

Key facts:
- **Cold by default.** Each subscriber gets its own subscription and its own run of the work. Two `sink`s on a network publisher make two requests (see `share()`, §8).
- **Publishers are value types** (mostly structs); operators wrap the upstream in a new struct (`Publishers.Map<Upstream, Output>`). That is why long chains produce huge types and why you `eraseToAnyPublisher()` at API boundaries.
- A stream completes at most once. After `.finished` or `.failure`, nothing more is delivered.
- `Failure == Never` means "cannot fail", which unlocks `assign(to:on:)`, `assign(to:)`, `switchToLatest()` and `.values`.

### Custom pieces, in one picture

```swift
struct MyPublisher: Publisher {
    typealias Output = Int
    typealias Failure = Never
    func receive<S: Subscriber>(subscriber: S) where S.Input == Int, S.Failure == Never {
        // build a Subscription, then subscriber.receive(subscription:)
    }
}
```
You almost never write one. Compose built-ins, or use a subject. Writing a `Subscription` correctly (demand, cancellation, thread-safety) is the hard part; the swift-mastery `taskPublisher` shows the small end of it.

---

## 2. Publishers you should know

| Publisher | Use |
|---|---|
| `Just(value)` | One value, then finished. `Failure == Never` |
| `Empty` | Finishes (or never finishes) without values |
| `Fail(error:)` | Fails immediately |
| `Future<Output, Failure>` | **Runs its closure on creation**, caches the single result. Eager, not lazy |
| `Deferred { … }` | Builds the inner publisher **per subscriber**, at subscription time |
| `Sequence` (`array.publisher`) | Emits the elements, then finishes |
| `@Published` projected value (`$name`) | Emits the current value on subscribe, then each `willSet` change |
| `URLSession.DataTaskPublisher` | `session.dataTaskPublisher(for: url)` |
| `NotificationCenter.Publisher` | `NotificationCenter.default.publisher(for: name)` |
| `Timer.TimerPublisher` | `Timer.publish(every:on:in:)` + `.autoconnect()` |
| KVO | `object.publisher(for: \.keyPath)` |
| `Publishers.Merge`, `CombineLatest`, `Zip` | Combine several upstreams (see §4) |

### `Future` and `Deferred`: the classic gotcha

```swift
func fetchEager() -> Future<Int, Never> {
    Future { promise in
        print("work starts NOW, even with no subscriber")
        promise(.success(42))
    }
}

func fetchLazy() -> some Publisher<Int, Never> {
    Deferred {                       // runs once per subscription
        Future { promise in
            print("work starts when subscribed")
            promise(.success(42))
        }
    }
}
```
- `Future` runs once, remembers the result and replays it to later subscribers. Wrap it in `Deferred` when you want a fresh run per subscriber (the usual case for requests).
- `Future` is **not cancellable**: cancelling the subscription does not stop the work inside. See the `taskPublisher` bridge in `Bridges.swift`, which cancels the underlying `Task`.

### `@Published`

```swift
final class Model: ObservableObject {
    @Published var query = ""        // $query is a Published<String>.Publisher
}
let model = Model()
let c = model.$query.sink { print($0) }   // prints "" immediately, then every change
model.query = "abc"
```
- It emits in **`willSet`**: inside the sink, `model.query` still returns the *old* value. Use the value you are given.
- It emits the current value on subscribe (hence `.dropFirst()` in most pipelines).
- Property wrapper in a class only (the projected publisher needs a stable object). Not the right tool in `@Observable` classes (R28 in the migration playbook).

---

## 3. Subscribers and cancellation

Built-ins: `sink`, `assign(to:on:)`, `assign(to:)` (Swift 5.5+, publishes into a `@Published` property).

```swift
final class ViewModel: ObservableObject {
    @Published var title = ""
    @Published var count = 0
    private var cancellables = Set<AnyCancellable>()

    init(source: some Publisher<String, Never>) {
        source
            .sink { [weak self] in self?.title = $0 }     // weak: self owns cancellables
            .store(in: &cancellables)

        source.map(\.count).assign(to: &$count)           // lifetime tied to the property, no AnyCancellable needed
    }
}
```

| Rule | Why |
|---|---|
| A subscription lives **only while its `AnyCancellable` lives** | Deallocating (or cancelling) the token cancels the upstream. Drop it by accident and the stream silently stops |
| Store tokens in a `Set<AnyCancellable>` owned by the object | `store(in:)` |
| `assign(to:on: self)` **retains `self` strongly** | A retain cycle when `self` stores the token. Use `assign(to: &$prop)` or `sink { [weak self] in … }` |
| `sink { self.x = $0 }` stored on `self` is a cycle too | Always `[weak self]` |
| `sink(receiveValue:)` exists only when `Failure == Never` | Otherwise handle the completion |

`AnyCancellable` calls `cancel()` on `deinit`. `Cancellable.cancel()` is idempotent and stops further delivery, but **work already started upstream may keep running** (`Future`, an unstructured `Task`): cancellation is cooperative.

### Custom subscriber and demand (back-pressure)

```swift
final class TwoAtATime: Subscriber {
    typealias Input = Int
    typealias Failure = Never
    private var subscription: Subscription?

    func receive(subscription: Subscription) {
        self.subscription = subscription
        subscription.request(.max(2))                    // start with two
    }
    func receive(_ input: Int) -> Subscribers.Demand {
        print(input)
        return .none                                     // or .max(1) to ask for one more
    }
    func receive(completion: Subscribers.Completion<Never>) { print("done") }
}
```
- `Subscribers.Demand`: `.unlimited`, `.max(n)`, `.none`. Demand is **additive** and can never be negative.
- `sink` and `assign` request `.unlimited`: no back-pressure. Back-pressure matters for custom subscribers and for operators like `buffer`, `collect`, `prefix`.
- Interview answer: "Combine has pull-based demand, so a slow subscriber can limit a fast publisher. In practice most code uses `.unlimited`, and I control volume with `debounce`, `throttle`, `removeDuplicates` or `buffer`."

---

## 4. Operators

Operators are publishers that wrap an upstream and return a new publisher. Group them by what they do.

**Transform:** `map`, `compactMap`, `flatMap`, `scan`, `reduce`, `collect`, `replaceNil`, `replaceEmpty`, `setFailureType`

**Filter:** `filter`, `removeDuplicates`, `first`, `last`, `prefix`, `dropFirst`, `drop(while:)`, `ignoreOutput`

**Combine streams:** `merge`, `combineLatest`, `zip`, `append`, `prepend`, `switchToLatest`

**Timing:** `debounce`, `throttle`, `delay`, `timeout`, `measureInterval`

**Errors:** `catch`, `tryCatch`, `retry`, `replaceError`, `mapError`, `assertNoFailure`, `tryMap`

**Threading and sharing:** `receive(on:)`, `subscribe(on:)`, `share`, `multicast`, `makeConnectable`, `eraseToAnyPublisher`

**Debugging:** `print`, `handleEvents`, `breakpoint`

### The four you must be able to explain

```swift
// map vs flatMap vs switchToLatest
let queries = PassthroughSubject<String, Never>()

queries
    .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)   // wait for a pause
    .removeDuplicates()                                                 // drop an unchanged value
    .map { search($0) }                  // Publisher of Publishers: AnyPublisher<[Hit], Never>
    .switchToLatest()                    // subscribe to the newest inner publisher, CANCEL the previous
    .sink { print($0) }
```

| Operator | Behavior | Typical use |
|---|---|---|
| `flatMap(maxPublishers:)` | Subscribes to **every** inner publisher; results interleave. `maxPublishers: .max(1)` queues-by-demand | Independent per-item work |
| `switchToLatest` | Only the latest inner publisher; **cancels** the old one | Search-as-you-type |
| `debounce(for:)` | Emits a value only after `d` of silence | Typing |
| `throttle(for:latest:)` | At most one per interval (first or latest in the window) | Scroll, button spam |

```swift
// combineLatest vs zip vs merge
let a = PassthroughSubject<Int, Never>(), b = PassthroughSubject<String, Never>()

a.combineLatest(b)   // (latest a, latest b) whenever either emits, after BOTH have emitted once
a.zip(b)             // pairs by index: (a1,b1), (a2,b2); waits for the slower side
a.merge(with: other) // same Output type; interleaves, no pairing
```

`scan` and `reduce`:
```swift
[1, 2, 3].publisher.scan(0, +)     // 1, 3, 6   emits each running total
[1, 2, 3].publisher.reduce(0, +)   // 6         emits once, on finish
```

`collect()` waits for `.finished`: on a never-ending subject it never emits. `collect(.byTime(…))` or `.byCount(n)` bounds it.

---

## 5. Errors: the rule that causes most bugs

**A failure completes the whole chain.** After `.failure`, the subscriber gets nothing more, even from a `PassthroughSubject` upstream.

```swift
// WRONG: one failed request kills the pipeline forever
queries
    .setFailureType(to: Error.self)
    .map { service.search($0) }                // AnyPublisher<[Hit], Error>
    .switchToLatest()
    .replaceError(with: [])                    // handles the error at the OUTER level, which has already completed
    .sink { show($0) }

// RIGHT: handle the failure inside the inner publisher, one request at a time
queries
    .map { query in
        service.search(query)
            .catch { _ in Just([]) }           // the inner publisher can't fail; the outer chain stays alive
    }
    .switchToLatest()                          // requires inner Failure == outer Failure (here Never)
    .sink { show($0) }
```

| Operator | Meaning |
|---|---|
| `catch { error -> Publisher }` | Replace the failed upstream with another publisher |
| `replaceError(with:)` | Turn a failure into one value, then **finish** |
| `retry(n)` | Resubscribe up to `n` times. Only useful with a *cold* upstream (`Deferred`); retrying a `Just` repeats nothing |
| `mapError` | Change the error type (e.g., `URLError` → `AppError`) |
| `tryMap` | A `map` that can throw: the `Failure` becomes `any Error` |
| `setFailureType(to:)` | Lets a `Never`-failing publisher join a failing chain |
| `assertNoFailure()` | Crashes on failure; debugging only |

```swift
// Typed networking pipeline
func load<T: Decodable>(_ url: URL, as type: T.Type) -> AnyPublisher<T, AppError> {
    URLSession.shared.dataTaskPublisher(for: url)
        .tryMap { data, response in
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AppError.badStatus
            }
            return data
        }
        .decode(type: T.self, decoder: JSONDecoder())
        .mapError { ($0 as? AppError) ?? .transport($0) }     // single error type for callers
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
}
```
`tryMap` erases the error type to `any Error`; Combine has no typed throws, so `mapError` is how you get back to a concrete type.

---

## 6. Subjects

A subject is **both a publisher and a way to push values in**: the bridge from imperative code into a stream.

| Subject | Stores | New subscriber receives |
|---|---|---|
| `PassthroughSubject<Output, Failure>` | nothing | only values sent **after** subscribing |
| `CurrentValueSubject<Output, Failure>` | the latest value (`.value`) | the current value, then later ones |

```swift
let events = PassthroughSubject<String, Never>()
events.send("lost")                       // no subscriber yet: gone
let c = events.sink { print($0) }
events.send("seen")                       // prints "seen"

let state = CurrentValueSubject<Int, Never>(0)
state.value = 1                           // same as send(1)
let d = state.sink { print($0) }          // prints 1 immediately
```

- Use `PassthroughSubject` for **events** (taps, notifications), `CurrentValueSubject` for **state** (a current value you can also read).
- Send completion with `send(completion:)`. After that, further `send` calls are ignored.
- `CurrentValueSubject.value` is thread-unsafe to mutate from several threads: serialize access.
- Prefer exposing `AnyPublisher` and keeping the subject `private`; callers should not be able to `send`.

```swift
final class Feed {
    private let subject = PassthroughSubject<Item, Never>()
    var items: AnyPublisher<Item, Never> { subject.eraseToAnyPublisher() }
}
```

---

## 7. Schedulers and threads

A `Scheduler` defines **where** and **when** closures run. `DispatchQueue`, `RunLoop`, `OperationQueue` conform, and so does `ImmediateScheduler`.

| Operator | Affects |
|---|---|
| `receive(on:)` | Where **downstream** work and delivery happen, from this point on |
| `subscribe(on:)` | Where the **subscription and upstream work** happen (rarely needed; `URLSession` already works off-thread) |
| `debounce`, `throttle`, `delay`, `timeout` | Take a scheduler to measure time on |

```swift
URLSession.shared.dataTaskPublisher(for: url)       // works on a URLSession queue
    .map(\.data)
    .decode(type: Item.self, decoder: JSONDecoder())  // still on that background queue
    .receive(on: DispatchQueue.main)                  // everything below runs on main
    .sink(receiveCompletion: { _ in }, receiveValue: { self.item = $0 })
```

- A Combine pipeline runs on **whatever thread the upstream emits on**, unless you `receive(on:)`.
- `receive(on: DispatchQueue.main)` always **hops** (async). `receive(on: ImmediateScheduler.shared)` doesn't.
- Update `@Published` properties that drive UI on the main thread.
- **Testing time-based operators:** `debounce(scheduler: DispatchQueue.main)` uses real time. Inject a generic `S: Scheduler` and use a controllable scheduler in tests (a hand-written `ManualScheduler`, or Point-Free's `combine-schedulers`). See `Tests/CombineSearchTests/TestSupport.swift`.

```swift
final class SearchModel<S: Scheduler> {
    init(scheduler: S, service: Service) {
        input
            .debounce(for: .milliseconds(300), scheduler: scheduler)   // test passes a manual scheduler
            …
    }
}
```

---

## 8. Sharing a stream: `share`, `multicast`, `makeConnectable`

By default each subscriber triggers its own upstream work.

```swift
let request = URLSession.shared.dataTaskPublisher(for: url)
request.sink { _ in } receiveValue: { _ in }   // request 1
request.sink { _ in } receiveValue: { _ in }   // request 2
```

| Tool | Behavior |
|---|---|
| `share()` | Shares one upstream subscription among subscribers (`multicast` + `autoconnect` + `PassthroughSubject`). **Late subscribers miss values already emitted**, and a finished share does not replay |
| `multicast(subject:)` + `connect()` | Same with your own subject and **manual** connect (`ConnectablePublisher`) |
| `.autoconnect()` | Connect when the first subscriber arrives (e.g., `Timer.publish`) |
| `makeConnectable()` | Turns a non-connectable publisher into one |

Gotchas:
- `share()` keeps the upstream running while **at least one** subscriber remains. Using it inside a view model can make "the view went away" no longer cancel an in-flight request (this exact bug is described in `notes/swift-6.4-combine-exercises.md`).
- There is no built-in "replay last value": use `multicast(CurrentValueSubject(…))` or store the value yourself.

---

## 9. Foundation and framework integration

```swift
// NotificationCenter
NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
    .sink { _ in refresh() }

// Timer
Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    .sink { date in print(date) }

// KVO
let c = player.publisher(for: \.status).sink { print($0) }

// JSON decoding (with dataTaskPublisher in §5)
.decode(type: Item.self, decoder: JSONDecoder())

// Publish a Result
Result<Int, Error>.success(1).publisher
```

SwiftUI:
- `.onReceive(publisher) { value in … }` subscribes for the life of the view.
- `ObservableObject` + `@Published` + `@StateObject` / `@ObservedObject` / `@EnvironmentObject` is Combine-backed state. `objectWillChange` is a Combine publisher the view observes.
- On iOS 17+, `@Observable` replaces this and does not use Combine.

---

## 10. Combine and Swift concurrency

### Combine → async

```swift
for await value in publisher.values { … }          // AsyncPublisher<…>
for try await value in failingPublisher.values { … }
```
- `.values` subscribes **when iteration starts**. With a `PassthroughSubject` you can miss values sent before the first `next()`.
- Cancelling the consuming task cancels the subscription.
- Ending the loop with `break` does not end an `AsyncStream` you wrap yourself while you still hold the stream (see `stream(of:)` in `Bridges.swift`).

### async → Combine

There is no first-party "publisher from an async function". The standard recipe:

```swift
func taskPublisher<T: Sendable>(_ op: @escaping @Sendable () async -> T) -> AnyPublisher<T, Never> {
    Deferred {
        Future { promise in
            Task { promise(.success(await op())) }
        }
    }
    .eraseToAnyPublisher()
}
```
Production version: also cancel the `Task` when the subscriber cancels (`handleEvents(receiveCancel:)`), or `switchToLatest` only *ignores* the old request.

### Swift 6 strict concurrency

- Combine's types (`Future.Promise`, subjects, `AnyCancellable`) are **not `Sendable`**.
- Keep a Combine pipeline on **one actor**, usually `@MainActor`; main-actor-isolated closures may capture non-`Sendable` state.
- Prefer that over `@preconcurrency import Combine` or `@unchecked Sendable`.
- A `Mutex` can hold a non-`Sendable` value you transfer in (it takes `sending`), which gives a `Sendable` box for an `AnyCancellable`.

### Decision guide: Combine or async/await?

| Situation | Choose |
|---|---|
| One-shot request/response | `async throws` |
| Debounce / throttle / dedupe / latest-wins over UI input | Either. Combine has the operators built in; async needs a hand-written or `swift-async-algorithms` operator and a cancel-the-previous task |
| `combineLatest` / `merge` of long-lived streams | Combine is simpler unless you take `swift-async-algorithms` |
| New SwiftUI state on iOS 17+ | `@Observable`, not `@Published` |
| Existing, tested Combine pipeline that works | Leave it; migrate with a test contract (R26–R29 in the playbook) |
| Library API surface | `async` / `AsyncSequence` for new API |

---

## 11. Debugging

```swift
publisher
    .print("search")                                          // logs subscribe, request, input, completion, cancel
    .handleEvents(
        receiveSubscription: { _ in print("subscribed") },
        receiveOutput: { print("out", $0) },
        receiveCompletion: { print("completion", $0) },
        receiveCancel: { print("cancelled") },
        receiveRequest: { print("demand", $0) }
    )
    .breakpointOnError()
```
- `print` and `handleEvents` do not change values; put them between operators to see where a value is lost.
- Long chains give unreadable types in errors: add `.eraseToAnyPublisher()` or break the chain into named steps.
- "Nothing happens" checklist: (1) is anything subscribed, (2) is the `AnyCancellable` stored, (3) did a failure already complete the stream, (4) is a scheduler delaying delivery, (5) is a `PassthroughSubject` sending before the subscription.

---

## 12. Testing Combine

```swift
@Test func collectsValues() {
    let subject = PassthroughSubject<Int, Never>()
    var received: [Int] = []
    let c = subject.sink { received.append($0) }

    subject.send(1); subject.send(2)
    #expect(received == [1, 2])
    c.cancel()
}
```
- Synchronous operators (`map`, `filter`, `scan`) are testable with no waiting.
- Asynchronous or time-based: inject the scheduler, advance it manually, and await outputs through a recorder or `.values`. **No `sleep`.**
- Test the contract, not the operators: the same test suite can run against a Combine pipeline and its `AsyncSequence` rewrite (`SearchContractTests`).
- Test cancellation: build a publisher with `handleEvents(receiveCancel:)` setting a flag, drop the token, assert the flag.
- Test deallocation: weak reference to the owner is `nil` after dropping it, which catches the `sink { self… }` cycle.

---

## 13. Pitfalls checklist

1. Forgetting to store the `AnyCancellable`: the pipeline cancels immediately.
2. `.sink { self.x = … }` stored on `self`, or `assign(to:on: self)`: retain cycle.
3. `replaceError` / `catch` **outside** `switchToLatest` / `flatMap`: the first error ends the pipeline.
4. `Future` is eager and cached: wrap in `Deferred`; and it cannot be cancelled.
5. `@Published` emits on `willSet` and replays the current value on subscribe.
6. `collect()` on an endless stream never emits.
7. `combineLatest` stays silent until every input has emitted once; `zip` waits for the slowest.
8. Updating UI state off the main thread: `receive(on: DispatchQueue.main)`.
9. `share()` keeps the upstream alive while any subscriber remains; late subscribers miss earlier values.
10. `PassthroughSubject` drops values sent before subscription; `.values` subscribes lazily.
11. Real-time schedulers in tests: inject the scheduler.
12. Swift 6: Combine is not `Sendable`. Keep it on `@MainActor`; no blanket `@unchecked`.

---

## 14. Questions and Answers

Practice each answer out loud in under 90 seconds.

**1. Walk me through what happens between `publisher.sink` and the first value.**
`sink` creates a `Subscribers.Sink` and calls `subscribe` on the publisher. The publisher builds a `Subscription` and calls `receive(subscription:)` on the subscriber. `sink` immediately calls `request(.unlimited)`. Only then does the publisher start work and call `receive(_:)` for each value, then one `receive(completion:)`. Nothing happens before the subscribe step, and the `AnyCancellable` that `sink` returns must stay alive or the subscription is cancelled.

**2. Why is a publisher "just a description", and what does "cold" mean?**
A publisher is a value (usually a struct) that describes how to produce values; it holds no running work. Each `subscribe` creates a new subscription and runs the work again, so two sinks on a `dataTaskPublisher` make two requests. That is "cold". `share()` or `multicast` makes it behave "hot", with one upstream shared by several subscribers.

**3. `Future` vs `Deferred { Future }`: when does the work start, and how many times does it run?**
`Future` runs its closure **when it is created**, even with no subscriber, runs it **once**, and replays the stored result to every subscriber. `Deferred { Future { … } }` builds a new `Future` for each subscription, so the work starts at subscribe time and runs once per subscriber. Neither cancels the inner work when the subscriber cancels; for that you need your own publisher or a `Task` cancelled in `handleEvents(receiveCancel:)`.

**4. Which of `map`, `flatMap`, `switchToLatest` for search-as-you-type, and why does `switchToLatest` need matching failure types?**
`map { search($0) }.switchToLatest()`. `map` turns each query into an inner publisher. `switchToLatest` subscribes to the newest one and **cancels** the previous, so stale responses can't arrive. `flatMap` would keep all inner publishers alive and interleave their results. Failure types must match because the operator forwards the inner publisher's failure through the outer stream; most code makes both `Never` by handling errors inside the inner publisher with `catch`.

**5. Search stopped working after one network error. What is the bug and the fix?**
A failure completes the whole chain. The code handled the error with `replaceError` or `catch` **after** `switchToLatest`, so the outer stream had already finished and later queries were ignored. Fix: handle the error **inside the inner publisher** (`service.search(q).catch { _ in Just([]) }` or map to a `Result`), so the outer pipeline never sees a failure. Add a regression test: fail one request, then send a good query and expect results.

**6. `PassthroughSubject` vs `CurrentValueSubject`: which for a button tap, which for "current filter"?**
`PassthroughSubject` for the tap: it is an event with no stored value, and late subscribers see nothing from before. `CurrentValueSubject` for the filter: it is state, holds the latest value (readable through `.value`) and replays it to each new subscriber.

**7. What is back-pressure in Combine, and does `sink` apply it?**
Subscribers request values with `Subscribers.Demand` (`.none`, `.max(n)`, `.unlimited`); a publisher may not send more than the outstanding demand. It is pull-based flow control. `sink` and `assign` request `.unlimited`, so they apply none. You get real back-pressure from custom subscribers and from operators such as `buffer`, `collect` and `prefix`; otherwise you limit volume with `debounce`, `throttle` or `removeDuplicates`.

**8. `receive(on:)` vs `subscribe(on:)`: what does each move?**
`receive(on:)` changes where everything **downstream** of it is delivered and executed; it is the one you use before updating UI (`DispatchQueue.main`). `subscribe(on:)` changes where the **subscription and upstream work** happen. It is rarely needed, because most sources (like `URLSession`) already work off the main thread.

**9. How do you test a `debounce` without waiting 300 ms?**
Make the pipeline generic over `S: Scheduler` and inject it. In tests pass a manual scheduler whose time only moves when the test calls `advance(by:)`, such as a hand-written `ManualScheduler` or Point-Free's `combine-schedulers`. Then assert: rapid input produces one output after 300 ms, each keystroke restarts the timer, and nothing is emitted at 299 ms. No `sleep`.

**10. How do you avoid a retain cycle in a view model that subscribes to its own publishers?**
The model owns a `Set<AnyCancellable>`, and a stored `sink { self.x = $0 }` captures `self`, which is a cycle. Use `[weak self]` in every `sink`, avoid `assign(to:on: self)` (it retains `self`), and prefer `assign(to: &$property)`, whose lifetime follows the property. Prove it with a test: create the model, keep a `weak` reference, drop the strong one, and expect `nil`.

**11. What does `share()` do, and what can go wrong with late subscribers?**
It shares one upstream subscription among all subscribers (`multicast` plus a `PassthroughSubject` plus `autoconnect`). Late subscribers miss values already emitted, and if the upstream finished, they get only the completion, so you get no replay. It also keeps the upstream alive while **any** subscriber remains, so dropping one subscriber doesn't cancel work that another subscriber still holds. Use `multicast(subject: CurrentValueSubject(…))` when you need a replay of the latest value.

**12. How do you consume a publisher with async/await, and what do you miss if you subscribe late?**
`for await value in publisher.values` (or `for try await` when the publisher can fail). `.values` subscribes when iteration starts, so with a `PassthroughSubject` any value sent before the first `next()` is lost. If that matters, subscribe eagerly with `sink` and feed an `AsyncStream` continuation, which buffers. Cancelling the consuming task cancels the subscription.

**13. Why isn't `AnyCancellable` `Sendable`, and how do you use Combine in a Swift 6 module without `@unchecked`?**
Combine predates Sendable checking: subjects, `Future.Promise` and `AnyCancellable` carry mutable, unsynchronized state, so the compiler can't treat them as safe to share across isolation domains. Keep a Combine pipeline on **one actor**, usually `@MainActor`, where closures may capture non-Sendable state. When a `@Sendable` closure such as `onTermination` needs the cancellable, put it in a `@MainActor` box (main-actor classes are `Sendable`) and hop with `Task { @MainActor in … }`, or move it into a `Mutex` through a `sending` parameter. No `@preconcurrency` or `@unchecked` needed.

**14. When would you still choose Combine in 2026, and when would you migrate?**
Keep Combine for existing, tested pipelines that work, for multi-stream operators such as `combineLatest` and `merge` where adding `swift-async-algorithms` isn't worth it, and where a framework still publishes. Choose async/await for one-shot requests and for new APIs, and `@Observable` for new SwiftUI state on iOS 17+. When migrating, write the behavior as a test contract first (debounce, stale response, error then recovery, teardown) and run it against both versions, so the rewrite is proven equivalent. Watch for the two bugs the compiler can't see: a cancelled task that still returns a value, and an error that used to end the pipeline.
