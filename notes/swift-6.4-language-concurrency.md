# Swift 6.4 Concurrency: Theory

- Exercises: [swift-6.4-concurrency-exercises.md](swift-6.4-concurrency-exercises.md) · Solutions: [swift-6.4-concurrency-exercises-responses.md](swift-6.4-concurrency-exercises-responses.md)
- Migration guide cheat sheet: `swiftmigrator/notes/swift6-concurrency.md`
- ⚙️ marks a behavior **verified on Swift 6.4.2** in this repo, often one that differs from what articles say.

## Contents

1. [The mental model in 5 sentences](#1-the-mental-model-in-5-sentences)
2. [The runtime: tasks, executors, the cooperative pool](#2-the-runtime-tasks-executors-the-cooperative-pool)
3. [Isolation](#3-isolation)
4. [Actors and reentrancy](#4-actors-and-reentrancy)
5. [Data-race safety: Sendable, regions, `sending`](#5-data-race-safety-sendable-regions-sending)
6. [Approachable concurrency (Swift 6.2+)](#6-approachable-concurrency-swift-62)
7. [Structured concurrency](#7-structured-concurrency)
8. [Cancellation](#8-cancellation)
9. [Async sequences and streams](#9-async-sequences-and-streams)
10. [Task context: locals, priority, naming](#10-task-context-locals-priority-naming)
11. [Swift 6.4 additions (and what actually ships)](#11-swift-64-additions-and-what-actually-ships)
12. [Bridging legacy code](#12-bridging-legacy-code)
13. [Testing concurrent code deterministically](#13-testing-concurrent-code-deterministically)
14. [Performance and debugging](#14-performance-and-debugging)
15. [Diagnostic decoder](#15-diagnostic-decoder)
16. [Evolution timeline](#16-evolution-timeline)
17. [Rapid-fire Q&A](#17-rapid-fire-qa)
18. [Talking points for the platform role](#18-talking-points-for-the-platform-role)

---

## 1. The mental model in 5 sentences

1. Every piece of mutable state belongs to exactly one **isolation domain**: an actor instance, a global actor such as `@MainActor`, or a single task.
2. Code runs **in** a domain, and it can only touch that domain's state synchronously. Reaching another domain is an `await`.
3. Values that cross between domains must be **`Sendable`** (safe to share) or **`sending`** (provably not shared anymore).
4. The compiler checks rules 1–3 statically in Swift 6 mode. That's **data-race safety**: low-level races become compile errors.
5. What the compiler does *not* check is **atomicity across `await`s** (reentrancy) and **ordering**. Those are your logic bugs to design away.

> Interview soundbite: "Swift 6 makes data races a compile-time error, not a runtime crash. It doesn't make concurrent code correct: every `await` is a point where the world can change, so I design actor methods so that no invariant spans a suspension point."

---

## 2. The runtime: tasks, executors, the cooperative pool

**Task.** The unit of asynchronous work. It has a priority, task-local values, a cancellation flag, and (if structured) a parent. Every `async` function runs as part of some task.

**Suspension.** At `await`, the function *may* suspend. Its frame (heap-allocated) is saved, and the thread is **returned to the pool** to run something else. This is why you never block in async code.

**Executors.** An executor decides *where* a job runs:

| Executor | Who uses it | Properties |
| --- | --- | --- |
| Global concurrent executor | nonisolated / `@concurrent` code, detached tasks | The cooperative pool: **one thread per CPU core**, no overcommit |
| Main actor's executor | `@MainActor` code | The main thread (main dispatch queue) |
| Default actor executor | every `actor` instance | Serial, runs on the cooperative pool threads |
| Custom executors | SE-0392 (`SerialExecutor`, `DispatchSerialQueue` as an executor), SE-0417 (task executor preference) | Bind an actor to a queue/thread; legacy interop |

**Why the cooperative pool matters.**
- GCD creates a new thread when a work item blocks. That leads to **thread explosion** (hundreds of threads, memory, context switches).
- Swift concurrency never overcommits. Blocking a pool thread (a semaphore, `Thread.sleep`, a synchronous network call) removes a whole core's worth of capacity. Block them all and you **deadlock**.
- Hence the rule: **never block in async code**. `DispatchSemaphore.wait()` to bridge async → sync is the classic interview trap.

**Hops.** Calling a function isolated to a different executor is a *hop*: the task suspends and gets enqueued on the target executor. Hops are cheap but not free (an enqueue, maybe a thread switch). Many tiny hops in a loop are a performance smell. Batch the work into one isolated call (an `isolated` parameter, an actor transaction).

**Continuations.** `withCheckedContinuation` suspends a task and hands you a resume handle. That's how callback APIs are bridged. You must resume **exactly once**: never resuming leaks the task forever, and resuming twice traps (checked) or corrupts memory (unsafe).

Interview questions:
- *"What happens to the thread at `await`?"* It's released back to the pool (if the task actually suspends); the continuation may resume on a different thread. Don't assume thread identity across `await`, and never use thread-local storage in async code.
- *"GCD vs Swift concurrency?"* Covered in [§14](#14-performance-and-debugging).

---

## 3. Isolation

### 3.1 The three kinds of domain

| Domain | Declared with | Calls from outside | Sendable? |
| --- | --- | --- | --- |
| Actor instance | `actor X` | `await x.method()` | actors are always `Sendable` |
| Global actor | `@MainActor`, `@globalActor actor SyncActor` | `await` unless already on it | isolated types are implicitly `Sendable` |
| Nonisolated | `nonisolated`, or the default in a library | synchronous | only touches `Sendable` state |

### 3.2 How isolation is inferred

- An `actor`'s members are isolated to `self` unless marked `nonisolated`.
- `@MainActor` on a type isolates all its members, extensions in the same declaration, and **closures written inside** it (closures inherit their context's isolation unless `@Sendable` or passed as a `sending` / `@Sendable` parameter).
- Subclasses inherit the superclass's global actor. Protocol conformance **used to** infer isolation (`View` → `@MainActor`); Swift 6 removed that outward inference except where the protocol declares it.
- With **default isolation** (SE-0466), unannotated declarations in the module are `@MainActor` (§6).

### 3.3 Synchronous code never hops

A synchronous function runs on its caller's executor. That's why:
- a synchronous nonisolated function can't touch actor state (it doesn't know where it runs);
- a synchronous nonisolated generic function **can** use a `@MainActor` isolated conformance when called from the main actor (§5.5).

### 3.4 `nonisolated`, `isolated` parameters, `#isolation`

- `nonisolated` on a member: callable synchronously from anywhere; may only read immutable `Sendable` state (`let`s). Needed to satisfy synchronous protocol requirements (`Hashable`, `CustomStringConvertible`).
  - ⚙️ An actor's `let` is implicitly nonisolated **only within its module**. From another module it needs `await` unless declared `nonisolated let`. The same goes for `@MainActor` classes.
- An `isolated` parameter (`func f(_ a: isolated MyActor)`): the function runs *on* `a`, so every access to `a` inside is synchronous. One hop for the caller and **no interleaving** between steps. The basis of actor "transactions":

  ```swift
  func transaction<T: Sendable>(_ body: @Sendable (isolated Self) throws -> T) rethrows -> T { try body(self) }
  ```
- `#isolation` (SE-0420) expands to the current isolation (`(any Actor)?`). As a default argument, `isolation: isolated (any Actor)? = #isolation` makes a function run on its caller's actor. That's the Swift 6.0 way to write helpers that accept non-Sendable closures; the stdlib uses it (`withTaskGroup(of:isolation:)`).
  - ⚙️ Such a function can't also be declared `nonisolated`.

### 3.5 Global actors and `assumeIsolated`

- A global actor (`@globalActor actor SyncActor { static let shared = SyncActor() }`) is a single serial domain that spans types and free functions. Use it when a subsystem's state is spread across several types that must call each other synchronously.
- `MainActor.assumeIsolated { }` / `actor.assumeIsolated { }`: synchronous, no hop. It checks the current executor at runtime and **traps** if wrong. Use it for callbacks whose thread is guaranteed by contract (main-queue delegate callbacks).
- `assertIsolated()` / `preconditionIsolated()`: checks only (debug / always).
- **Dynamic isolation checks (SE-0423).** When Swift 6 code is called from unchecked code (ObjC, Swift 5 modules), the compiler inserts runtime checks at isolation boundaries. That's where `_dispatch_assert_queue_fail` crashes come from during migrations.

Interview questions:
- *"Why is `@MainActor` on a view model good, and when is it bad?"* Good: UI state belongs to one domain, there are no Sendable fights, and SwiftUI reads it on main. Bad: when the type does heavy work in synchronous methods (it blocks the UI). Move that work into `@concurrent` functions, not the whole type off the main actor.

---

## 4. Actors and reentrancy

### 4.1 What an actor guarantees

- One task executes on the actor at a time (mutual exclusion **between suspension points**).
- State is accessed only from inside (the compiler enforces it).
- It does **not** guarantee that a method runs from start to finish without other calls interleaving. At each `await` inside the actor, other queued calls can run.

### 4.2 Why reentrancy is the design

Non-reentrant actors would deadlock on cycles (A awaits B, B awaits A) and block every caller during slow I/O (priority inversion). Swift chose reentrancy: no deadlocks, but **interleavings** you must reason about.

### 4.3 The bug pattern and the three fixes

```swift
// ❌ read → await → write based on the stale read
if cache[id] == nil {
    let value = try await fetch(id)   // other calls run here
    cache[id] = value                 // N callers fetched N times
}
```

| Fix | When | Example (C03) |
| --- | --- | --- |
| Make the critical section synchronous | the check-and-mutate doesn't need I/O | `func increment() { count += 1 }` instead of `get` + `set` |
| Record intent **before** the `await` | dedup, reservations | an in-flight `[ID: Task]` dictionary; a *hold* on nights, rolled back on failure |
| Re-validate **after** the `await` | the state may have changed legitimately | `guard cache[id] == nil else { return cache[id]! }` after the fetch |

> Review rule: *"Inside an actor, no decision may depend on state read before an `await`."*

### 4.4 Testing reentrancy deterministically

Prove the bug first, with a barrier: the fetch closure awaits `AsyncBarrier(count: 5)`, which only opens once all 5 callers are inside the fetch. The naive version provably fetches 5 times. The fixed version is tested with parameterized runs (`@Test(arguments: 0..<20)`) and a dedup counter.

### 4.5 Actors vs other tools

| Need | Tool |
| --- | --- |
| Shared mutable state, async access, longer operations | `actor` |
| UI state | `@MainActor` class (usually `@Observable`) |
| Tiny critical sections callable from **sync** code | `Mutex` (Synchronization, iOS 18 / macOS 15) |
| Lock-free counters, flags | `Atomic` (SE-0410) |
| Immutable shared data | `final class X: Sendable` with `let`s, or a struct |

Interview questions:
- *"Is an actor a lock?"* No. A lock gives exclusive access for a whole critical section, including blocking waits. An actor gives exclusive access only between suspension points and never blocks a thread: waiting callers are suspended tasks, not blocked threads.
- *"Actor vs serial DispatchQueue?"* The compiler-checked isolation, no thread blocking, priority escalation, and reentrancy (a queue with `sync` deadlocks instead).

---

## 5. Data-race safety: Sendable, regions, `sending`

### 5.1 `Sendable`

A type is `Sendable` when sharing values of it across domains can't cause a data race.

| Rung | Example | Notes |
| --- | --- | --- |
| Value type with Sendable members | `struct Quote: Sendable` | implicit for non-public types; **write it explicitly for `public`/`package`** |
| Immutable `final class` | `final class ExchangeRates: Sendable { let … }` | must be `final`, all stored properties `let` + `Sendable` |
| Isolated type | `actor`, `@MainActor class` | the actor protects the state |
| `Mutex`-protected | `final class RateLimiter: Sendable { let state: Mutex<State> }` | the state lives *inside* the lock, so the compiler proves every access is locked |
| `@unchecked Sendable` | a class with an `NSLock` | the compiler trusts you; needs a comment naming the lock |

Function types: `@Sendable` closures may capture only `Sendable` values, and only **immutably** (⚙️ *"mutation of captured var 'count' in concurrently-executing code"*). Metatypes: `SendableMetatype` (6.2) for generic code that sends `T.Type`.

Global and static variables: must be `let` of a `Sendable` type, isolated to a global actor, or `nonisolated(unsafe)` with a justification.

### 5.2 Regions (SE-0414)

The compiler tracks which non-Sendable values might reference each other (a **region**). Rules of thumb:
- A freshly created value starts in its own **disconnected** region.
- Storing, passing two values to one call, or capturing them in one closure **merges** their regions.
- Actor-isolated state is one permanent region; a value merged into it never leaves.
- A disconnected region can be **transferred** across a boundary (passed to an actor or captured by a `Task`). After that, using it on the old side is an error: *"sending 'x' risks causing data races"*.

So this compiles without `Sendable` anywhere:

```swift
let draft = ReservationDraft(…)      // disconnected
await outbox.submit(draft)           // transferred into the actor's region
// draft.notes.append("x")          // ❌ would be an error here
```

⚙️ **Gotchas verified on 6.4.2:**
- Region errors come from a **SIL pass**: `swiftc -typecheck` won't show them; a real build does.
- An initializer that takes a non-Sendable argument keeps its result **connected** to that argument. `return ReservationDraft(copying: first)` from an actor is *"task or actor-isolated value cannot be sent"*. Copy the `Sendable` fields out first.
- Values captured by a `Task` closure belong to that closure's region and **can't be re-sent** to an actor from inside it (a closure might run more than once).

### 5.3 `sending` (SE-0430)

`sending` makes the region rule part of a signature:
- `func f(_ x: sending T)`: the caller must pass a disconnected value, and the callee may transfer it anywhere.
- `func make() -> sending T`: the result is disconnected, so the caller can send it on.
- `Task.init`, `Task.detached`, `TaskGroup.addTask` and `CheckedContinuation.resume(returning:)` take `sending` values/closures. That's why you can move a non-Sendable value into a task.

`Sendable` vs `sending`: **type** property ("always safe to share") vs **value** property ("nobody else holds this now").

### 5.4 Unsafe opt-outs, ranked

| Opt-out | Meaning | Acceptable when |
| --- | --- | --- |
| `@preconcurrency import` | downgrade diagnostics from a module | the module isn't yours / isn't migrated |
| `@preconcurrency` conformance | conformance with runtime isolation checks | the protocol isn't yours |
| `@unchecked Sendable` | "trust me" | you can name the lock guarding every mutable property |
| `nonisolated(unsafe)` | unchecked global/stored property | guarded by an external lock |
| `MainActor.assumeIsolated` | runtime-checked synchronous isolation | the thread is guaranteed by contract |

### 5.5 Isolated conformances (SE-0470, Swift 6.2)

`extension ListingCardModel: @MainActor PriceDisplaying` declares a conformance that only exists on the main actor. Generic code can use it when it runs on the main actor, including a nonisolated *synchronous* generic called from main. Off the main actor it's an error: ⚙️ *"main actor-isolated conformance of 'X' to 'P' cannot be used in @concurrent context"*.

This replaces three bad pre-6.2 workarounds: `nonisolated` witnesses (no state access), `@preconcurrency` conformances (runtime traps), and `@MainActor` protocols (contagious).

Interview questions:
- *"A struct holding a class reference: Sendable?"* Only if the class is `Sendable`. Otherwise it's a shared mutable reference in disguise.
- *"Why is `@unchecked Sendable` a last resort?"* It turns off checking forever, for every future edit of the type. `Mutex` gives the same flexibility with compiler checking.

---

## 6. Approachable concurrency (Swift 6.2+)

The goal: **single-threaded by default, concurrent when you ask for it**. Three pieces:

### 6.1 Default `MainActor` isolation (SE-0466)

```swift
.target(name: "App", swiftSettings: [.defaultIsolation(MainActor.self)])   // -default-isolation MainActor
```

- Every unannotated declaration in the module is `@MainActor`, so it's implicitly `Sendable`, and most Sendable errors disappear (everything lives in one domain).
- Opt out with `nonisolated` on types (DTOs, parsers, pure logic) and `@concurrent` on functions that must run in the background.
- **Use for:** app targets and UI feature modules. **Don't use for:** libraries, networking, persistence and SDKs. Making their API main-actor isolated would leak into every client.
- Xcode 26+ turns it on for **new app targets**; SwiftPM's default stays nonisolated.

### 6.2 `nonisolated(nonsending)` and `@concurrent` (SE-0461)

| | Swift 5.7–6.1 (SE-0338) | With `NonisolatedNonsendingByDefault` |
| --- | --- | --- |
| `nonisolated func f() async` | runs on the **global executor** | runs on the **caller's actor** |
| non-Sendable arguments | cross a boundary (errors) | stay in the caller's domain (fine) |
| "run in the background" | implicit | explicit: `@concurrent func f() async` |

⚙️ Verified on 6.4.2 from a `@MainActor` caller: a plain `nonisolated async` function runs off the main thread under Swift 6 defaults and **on** it with the feature on. `@concurrent` always runs off. `@concurrent` on a sync function: *"cannot use @concurrent on non-async global function"*.

You can spell the new behavior explicitly, independent of settings: `nonisolated(nonsending) func f() async`.

**Migration risk:** code that relied on the implicit hop (decoding, image work in `nonisolated async` functions called from the UI) silently moves **onto the main actor**. That isn't a compile error; it shows up as hangs. Use `swift package migrate --to-feature NonisolatedNonsendingByDefault` (the feature is marked `migratable`): it adds `@concurrent` where the old behavior must be kept. Then profile.

### 6.3 The "Approachable Concurrency" build setting

`SWIFT_APPROACHABLE_CONCURRENCY = YES` enables these upcoming features:
- `NonisolatedNonsendingByDefault`
- `InferIsolatedConformances`: in a main-actor module, conformances of main-actor types are inferred `@MainActor`. ⚙️ That's why a DTO without `nonisolated` can't be decoded in a `@concurrent` function.
- `InferSendableFromCaptures`, `GlobalActorIsolatedTypesUsability` and `DisableOutwardActorInference`, which Swift 6 mode already enables.

Default isolation is a separate setting (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

This repo's `ConcurrencyApp` target reproduces it in SwiftPM:

```swift
swiftSettings: [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]
```

### 6.4 Other 6.2 lifecycle tools

- **`isolated deinit` (SE-0371).** A regular `deinit` is always nonisolated (the last release can happen on any thread). `isolated deinit` runs on the actor: ⚙️ **inline** if the last release happens on it, **enqueued** otherwise. Never rely on `deinit` timing.
- **`Task.immediate` (SE-0472).** Starts running synchronously on the caller's executor until the first real suspension. ⚙️ Right after `Task.immediate { log("started"); … }` returns, the log already holds `"started"`; after `Task { … }` it doesn't. Fixes "the spinner appears one frame late" and ordering races in UI handlers.
- **Task names (SE-0469).** `Task(name: "sync-listings") { … }`; shown in Instruments and debuggers.
- **`weak let` (SE-0481).** An immutable weak reference, which keeps a class `Sendable`.

Interview questions:
- *"What does 'approachable concurrency' change for a team migrating to Swift 6?"* Most UI code needs no annotations (everything is main-actor). The work becomes finding the few places that should run in the background and marking them `@concurrent`, which is a performance task, not a correctness fight. The risk is accidental main-thread work; mitigate it with Instruments and hang reports.

---

## 7. Structured concurrency

### 7.1 The rule

A **child task** can't outlive its scope. When the scope ends, unfinished children are cancelled **and awaited**. This makes resource lifetimes, error propagation, cancellation and task-locals sound: like a function call tree, but concurrent.

### 7.2 `async let` vs task groups

| | `async let` | `withTaskGroup` / `withThrowingTaskGroup` |
| --- | --- | --- |
| Number of children | fixed at compile time | dynamic |
| Result types | can differ | one type (use an enum to mix) |
| Result order | **the order you `await`** | **completion order** (`for await`, `next()`) |
| Fail fast | no: an error surfaces only when that child is awaited | yes: the first thrown error ends the loop, siblings are cancelled |
| Typical use | "load profile, listings and reviews for this screen" | fan-out over a collection, hedged requests, racing |

⚙️ C13 proves the ordering: with `async let`, a fast failure in `fees` is only seen after the gated `nightly` finishes.

**Patterns:**
- **Hedged request / first wins:** add one task per mirror, take the first non-nil `next()`, then `cancelAll()`.
- **Bounded concurrency:** seed N tasks; on each completion add one more. Capture the item in a `let`, never a shared index.
- **Timeout:** race the operation against `clock.sleep(for:)` in a throwing group; whichever finishes first wins; cancel the other.
- **Discarding groups (SE-0381):** `withDiscardingTaskGroup` never stores results, so memory stays flat for endless loops (servers, event processors); the first error cancels the group.

### 7.3 Unstructured tasks

| | Inherits actor | Priority | Task-locals | Cancellation from creator |
| --- | --- | --- | --- | --- |
| child (`async let`, group) | runs concurrently (nonisolated) | yes | yes | **yes** |
| `Task {}` | **yes** | yes | yes | no |
| `Task.detached {}` | no | no | no | no |
| `Task.immediate {}` | yes, and starts synchronously | yes | yes | no |
| `@concurrent` function call | no (global executor) | yes | yes | yes (it's just a call) |

Use `Task {}` to bridge from sync code (button handlers) into async. **Store** it if it can outlive the UI (`self.loadTask = Task { … }` and `cancel()` in `onDisappear`), or prefer SwiftUI's `.task {}` modifier, which cancels on disappear. `Task.detached` is rarely right: it drops priority and task-locals. Prefer a `@concurrent` function.

### 7.4 Long-lived tasks and leaks

A `Task` strongly captures what it uses for as long as it runs. A view model that starts `Task { for await x in stream { self.apply(x) } }` keeps `self` alive forever if the stream never ends. Fixes:
1. Tie it to the view: `.task { await model.observe() }` (cancelled automatically).
2. Store the task and cancel it.
3. Capture `[weak self]` *inside* the loop (re-check `self` on each element).

Avoid `unowned` in task closures: the task can outlive the object, and then it crashes.

Interview questions:
- *"What happens if you never await an `async let`?"* It's cancelled and awaited implicitly at scope exit. It never leaks, but the scope waits.
- *"How do you limit concurrency in a task group?"* The sliding-window pattern (C20).

---

## 8. Cancellation

- `task.cancel()` sets a flag on the task **and all its structured descendants**, then runs their cancellation handlers. It never stops code by itself.
- Polling: `Task.isCancelled` (return partial work) or `try Task.checkCancellation()` (throw `CancellationError`).
- Most stdlib and Foundation async APIs (`Task.sleep`, `URLSession`, `AsyncStream` iteration) are cancellation-aware: they throw, or return `nil`/end.
- **`withTaskCancellationHandler(operation:onCancel:)`** forwards cancellation to legacy APIs. `onCancel` runs **immediately and concurrently** on the cancelling thread, or *before* the operation if the task is already cancelled. ⚙️ The bridged object must remember "cancelled" so a later `start` fails fast, or the task hangs (C14).
- A child created in a cancelled task is cancelled immediately; `Task {}` and `Task.detached` are not (⚙️ C14).
- **Cleanup under cancellation** is its own problem: `defer { await … }` (6.4) runs, but in the cancelled task (§11).

Interview questions:
- *"A user scrolls fast through 200 listings; each cell starts an image download. How do you avoid 200 downloads?"* Use `.task(id:)` per cell, so it's cancelled on disappear. The download is cancellation-aware (`URLSession` async). Add an in-flight dedup actor so two cells with the same URL share one task. Keep a bounded number of concurrent downloads.

---

## 9. Async sequences and streams

- `AsyncSequence` / `AsyncIteratorProtocol`: `for await` / `for try await`. Since SE-0421 (Swift 6.0) they have a typed `Failure` (`some AsyncSequence<Listing, Never>`) and `next(isolation:)`, so iterators run on the caller's actor (no hop per element) and non-throwing sequences don't need `try`.
- **`AsyncStream.makeStream(of:bufferingPolicy:)`** (SE-0388): the standard bridge from delegates, callbacks and notifications.
  - `onTermination` runs when the consumer stops (cancelled, finished, or the stream is dropped). Remove the observer there, or it leaks.
  - Buffering: `.unbounded` (default; every element, memory risk), `.bufferingNewest(n)` (latest state, e.g. progress or location), `.bufferingOldest(n)`.
  - **Unicast:** two iterators *split* the elements. Create one stream per subscriber for broadcast.
- `AsyncThrowingStream` ends with `finish(throwing:)`.
- **`Observations` (SE-0475, iOS/macOS 26):** `Observations { model.price }` is an async sequence of values from `@Observable` reads. It emits the current value first, then **transactionally**: ⚙️ several synchronous mutations produce one value.
- **swift-async-algorithms:** `debounce`, `throttle`, `merge`, `combineLatest`, `AsyncChannel` (backpressure). It's the Combine-operator replacement.

Interview questions:
- *"Combine vs async sequences?"* Combine: push-based, rich operators, `AnyCancellable` lifetimes, no compiler-checked isolation. Async sequences: pull-based (natural backpressure), structured cancellation, isolation-checked. New code uses async sequences plus `Observations`; Combine remains for legacy `@Published` pipelines.

---

## 10. Task context: locals, priority, naming

- **`@TaskLocal`** (SE-0311): `static var requestID: String?`, bound with `$requestID.withValue("req-1") { … }` for a scope. Children and `Task {}` inherit it; `Task.detached` doesn't (⚙️ C18). Good for tracing, logging and test overrides; bad for business inputs (invisible in signatures).
- **Priority:** children inherit it. Awaiting a lower-priority task, or an actor holding work a higher-priority task waits for, **escalates** it (this avoids priority inversion). SE-0462 (6.2): `withTaskPriorityEscalationHandler` to observe escalation (for example, to bump a `URLSessionTask`) and `task.escalatePriority(to:)` to trigger it.
- **Names** (SE-0469): `Task(name:)`, `group.addTask(name:)`. They show up in Instruments' Swift Concurrency template.

---

## 11. Swift 6.4 additions (and what actually ships)

| Feature | Proposal | ⚙️ Status on 6.4.2 / macOS 26 |
| --- | --- | --- |
| `await` inside `defer` | SE-0493 | **Works.** 6.3.2 rejects it (*"'async' call cannot occur in a defer body"*). The cleanup runs in the same task, so after cancellation `Task.isCancelled == true` inside it |
| `withTaskCancellationShield { }` and `Task.hasActiveCancellationShield` | SE-0504 | In the stdlib, `@available(anyAppleOS 27.0, *)`. **A binary that contains the call fails to launch on macOS 26**, even behind `if #available(macOS 27, *)`: *dyld: Symbol not found `_swift_task_cancellationShieldPop`*. Usable only with a 27 deployment target |

**Why both are needed.** "Release the server lease on every exit path" needs:
1. **Always runs:** `defer { await lease.release() }`.
2. **Can finish when cancelled:** the shield. Without it, `release()`'s network call sees cancellation and throws immediately.

```swift
defer { await withTaskCancellationShield { await lease.release() } }   // iOS 27+
defer { await Task { await lease.release() }.value }                    // portable: an unstructured task ignores cancellation
```

The portable version costs a task allocation and a hop, and the work becomes unstructured (it can outlive the caller if the caller stops awaiting). The shield keeps the same task.

The rest of the 6.4 release is language-level: `any P?`, module selectors, `@diagnose`, noncopyable `Equatable`/`Hashable`, `UniqueArray` / `UniqueBox`, Swift Build as the default build system.

---

## 12. Bridging legacy code

| Legacy | Modern | Notes |
| --- | --- | --- |
| completion handler | `async` + `withCheckedThrowingContinuation` | resume exactly once on every path; keep the callback API, deprecated (library) |
| delegate / multicast callbacks | `AsyncStream` + `onTermination` | one stream per subscriber |
| `DispatchQueue.main.async` around UI | `@MainActor` type | remove the dispatch wrappers |
| serial queue protecting state | `actor` (async callers) or `Mutex` (sync callers) | `DispatchSerialQueue` can also be an actor's executor |
| `DispatchQueue.global().async` for CPU work | `@concurrent` function | structured, keeps priority and task-locals |
| `DispatchGroup` | task group | |
| `DispatchSemaphore` to wait for async | **never**; make the caller async | blocks a pool thread, risks deadlock |
| `Timer` / polling loop | `for await` over `AsyncTimerSequence` or `clock.sleep` in a loop, with an injected clock | cancellable |
| `OperationQueue.maxConcurrentOperationCount` | bounded task group | |
| `NotificationCenter` observer | `NotificationCenter.notifications(named:)` async sequence | |
| `ObservableObject` + `@Published` | `@Observable` + `Observations` | iOS 17 / 26 |

Unmigrated modules: `@preconcurrency import`, a retroactive `@unchecked Sendable` with a removal condition, and the target kept in `.swiftLanguageMode(.v5)`. See the migration playbook (`swiftmigrator/playbook/MIGRATION_PLAYBOOK.md`, v2).

---

## 13. Testing concurrent code deterministically

Principle: **a test proves an ordering; it never hopes for one.** No `sleep`.

| Tool | Proves | In this repo |
| --- | --- | --- |
| **Gate** (an actor that suspends `wait()` until `open()`) | "X is suspended at this point" | `AsyncGate` |
| **Barrier** (resumes when N tasks have arrived) | "these N things are concurrent" (reproduces races) | `AsyncBarrier` |
| **Streams as signals** | "step 1 happened before I do step 2" | `AsyncStream.makeStream` in C14/C19 |
| **Injected clock** | time-based logic (backoff, timeouts, debounce) | `ManualClock` with `waitForSleepers` |
| **Cancellation without timers** | "this blocks until cancelled" | `suspendUntilCancelled()`, iterating an empty `AsyncStream` |
| **Parameterized repetition** | an invariant holds across interleavings | `@Test(arguments: 0..<20)` |
| **Bounded yield loops** | eventually-consistent state, failing instead of hanging | `eventually { … }` |

Swift Testing specifics:
- `@MainActor` on a test or suite runs it on the main actor.
- `confirmation(expectedCount:)` for events.
- `.timeLimit(.minutes(1))` as a safety net.
- Tests run **in parallel by default**: shared registries need unique IDs per test.
- `swift test` 10× in a row before calling concurrency code done.

Prove the bug first: a reentrancy fix is only convincing if the same test harness shows the naive version failing (C03).

---

## 14. Performance and debugging

**GCD vs Swift concurrency:**

| | GCD | Swift concurrency |
| --- | --- | --- |
| Safety | none (races are runtime bugs) | compile-time data-race safety |
| Threads | grows on blocking (thread explosion) | one per core, never overcommits |
| Blocking | tolerated (spawns threads) | forbidden (starves the pool) |
| Cancellation | manual flags | structured, propagates |
| Priority | QoS, inversion possible | escalation built in |
| Interop | everywhere | bridges via continuations / executors |

**Instruments:**
- **Swift Concurrency template:** task lifetimes, task states (running / suspended / enqueued), actor queue depth, task names. Use it to find tasks that never end (leaks) and actors that are bottlenecks.
- **Hangs / Time Profiler:** main-thread work after enabling `NonisolatedNonsendingByDefault` or default `MainActor` isolation.
- **Leaks / Allocations / memory graph:** long-lived tasks capturing `self` (§7.4).

⚙️ **Starvation seen for real** (BookingSync capstone): a reader-writer `DispatchQueue` store (`queue.sync` reads, barrier writes) behind `@unchecked Sendable` compiled cleanly, then **deadlocked** when 20 parameterized test cases ran in parallel. `sample <pid>` showed 16/16 cooperative threads (one per core) blocked in `_dispatch_sync_f_slow` behind a barrier that never got a thread. The fix was an `OSAllocatedUnfairLock`. The lesson: `@unchecked Sendable` silences the compiler, not the runtime.

**Common performance smells:**
- an `await` per element in a hot loop across actors (batch it into one isolated call);
- actor contention (one actor everyone awaits) → shard it, make reads `nonisolated` on immutable data, or use a `Mutex` for tiny sections;
- `Task.detached` everywhere (loses priority);
- unbounded task groups.

**Runtime diagnostics:** Thread Sanitizer still catches races in `@unchecked`/unsafe code. `SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE` and dynamic isolation checks surface wrong-thread calls from ObjC.

---

## 15. Diagnostic decoder

The skill the plan asks for: explain any concurrency diagnostic. Each row is the message, what the compiler reasoned, and the usual fix. Rows marked ✓ are reproduced in `CompileFailures/`.

| Diagnostic (substring) | What the compiler proved | Typical fix |
| --- | --- | --- |
| ✓ `var '…' is not concurrency-safe because it is nonisolated global shared mutable state` | any thread can read and write it | `let`, isolate to `@MainActor`, or move into an actor |
| ✓ `stored property '…' of 'Sendable'-conforming class '…' is mutable` | a `var` in a shared class | `let`, a `Mutex`, or an actor |
| ✓ `non-final class '…' cannot conform to the 'Sendable' protocol` | a subclass could add state | `final` |
| ✓ `mutation of captured var '…' in concurrently-executing code` | an `@Sendable` closure shares a `var` | capture a `let` copy, or move the state into an actor |
| ✓ `actor-isolated property '…' can not be referenced from a nonisolated context` | sync access from outside the actor (⚙️ including another module's access to an actor `let`) | `await`, or `nonisolated let` for immutable data |
| ✓ `main actor-isolated property '…' can not be mutated from a nonisolated context` | UI state touched from the background | make the caller `@MainActor` or `await` |
| ✓ `call to main actor-isolated … in a synchronous nonisolated context` (in `deinit`) | `deinit` is nonisolated | `isolated deinit`, or capture what's needed into a `Task` |
| ✓ `sending '…' risks causing data races` | a non-Sendable value is still used, or still reachable, after crossing a boundary | stop using it after sending; make it `Sendable`; send a copy built from Sendable values |
| ✓ `task or actor-isolated value cannot be sent` | the value belongs to an actor or task region (⚙️ also results of inits that took a connected argument) | return a fresh value built from Sendable parts |
| ✓ `passing closure as a 'sending' parameter risks causing data races` | a `Task` captures something the caller still owns | `sending` parameter, `Sendable` type, or don't capture it |
| ✓ `conformance of '…' to protocol '…' crosses into main actor-isolated code` | a nonisolated protocol witnessed by main-actor code | `extension T: @MainActor P` (6.2), `nonisolated` witnesses, or `@preconcurrency` |
| ✓ `main actor-isolated conformance of '…' to '…' cannot be used in @concurrent context` | an isolated conformance used off its actor (⚙️ e.g. `Decodable` in a main-by-default module) | `nonisolated` on the type, or keep the work on the main actor |
| ✓ `global function with 'isolated' parameter cannot be 'nonisolated'` | contradictory isolation | drop `nonisolated` |
| ✓ `cannot use @concurrent on non-async …` | sync code can't switch executors | make it `async` or drop `@concurrent` |
| `main actor-isolated default value in a nonisolated context` | an initializer default requires main | isolate the container or the init |
| `capture of '…' with non-Sendable type '…' in a '@Sendable' closure` | sharing a non-Sendable value | make it `Sendable`, or use `sending`/regions |
| `expression is 'async' but is not marked with 'await'` | crossing into another domain | `await` (and re-check atomicity) |
| `'async' call cannot occur in a defer body` | pre-6.4 compiler | upgrade, or restructure with `do`/`catch` |
| Runtime: `_dispatch_assert_queue_fail` / *"Incorrect actor executor assumption"* | dynamic isolation check: called on the wrong thread from unchecked code | fix the caller's thread; a `nonisolated` override; file a bug with the library |

---

## 16. Evolution timeline

| Swift | Concurrency milestones |
| --- | --- |
| 5.5 (2021) | async/await (SE-0296), actors (SE-0306), structured concurrency (SE-0304), `Sendable` (SE-0302), global actors (SE-0316), `AsyncStream` (SE-0314), task-locals (SE-0311) |
| 5.7 | `nonisolated async` runs on the global executor (SE-0338); `Clock`/`Duration` (SE-0329); `any` (SE-0335) |
| 5.9 | custom executors (SE-0392), `DispatchSerialQueue` as an executor, discarding task groups (SE-0381), `AsyncStream.makeStream` (SE-0388), `@Observable` (SE-0395) |
| 5.10 | complete strict-concurrency checking in Swift 5 mode; `nonisolated(unsafe)` (SE-0412) |
| 6.0 (2024) | **Swift 6 language mode: data-race safety by default**; region isolation (SE-0414), `sending` (SE-0430), `#isolation` (SE-0420), `@isolated(any)` (SE-0431), typed `AsyncSequence` (SE-0421), `Mutex` (SE-0433), `Atomic` (SE-0410), task executor preference (SE-0417), dynamic isolation checks (SE-0423) |
| 6.1 | `nonisolated` on types and extensions, `TaskGroup` child-type inference |
| 6.2 (2025) | **Approachable concurrency:** default isolation (SE-0466), `nonisolated(nonsending)` / `@concurrent` (SE-0461), isolated conformances (SE-0470), `isolated deinit` (SE-0371), `Task.immediate` (SE-0472), task names (SE-0469), priority escalation APIs (SE-0462), `Observations` (SE-0475), `weak let` (SE-0481), `swift package migrate` |
| 6.3 | module selectors (language); continued diagnostics polish |
| 6.4 (2026) | `await` in `defer` (SE-0493), task cancellation shields (SE-0504, runtime on OS 27) |

---

## 17. Rapid-fire Q&A

**Is `async` the same as "runs in the background"?** No. `async` means "may suspend". Where it runs is decided by isolation: `@MainActor async` runs on main, `@concurrent` runs on the pool, and with `nonisolated(nonsending)` it runs wherever the caller is.

**Does `await` always suspend?** No. It's a *potential* suspension point. If the callee is on the same executor and doesn't suspend, no hop happens. But you must reason as if it does.

**`Task {}` inside a `@MainActor` method: where does the closure run?** On the main actor (it inherits isolation). Heavy work inside it blocks the UI. Use a `@concurrent` function.

**Why can't I call an actor method synchronously from a `nonisolated` function?** You aren't on the actor, and getting onto it requires a hop, which requires `await`.

**What makes a type `Sendable` implicitly?** Non-public structs/enums whose members are all `Sendable`, actors, and global-actor-isolated types. Public types must declare it.

**Actor reentrancy in one sentence?** At every `await` inside an actor, other calls can run, so invariants must not span suspension points.

**`Mutex` or actor?** `Mutex` if callers are synchronous or the critical section is tiny; actor if callers can `await` and the operations are larger.

**What's a region?** A group of non-Sendable values that may alias. A disconnected region can be transferred across isolation boundaries once.

**`sending` vs `@Sendable`?** `sending`: this *value* is transferred (non-Sendable types allowed). `@Sendable`: this *closure* can be called concurrently (captures must be Sendable).

**What did Swift 6.2 change about `nonisolated async`?** With `NonisolatedNonsendingByDefault`, it runs on the caller's actor; `@concurrent` opts back into the global executor.

**When is default `MainActor` isolation wrong?** In libraries and non-UI modules: it makes their API main-actor isolated for every client.

**`async let` vs task group?** Fixed vs dynamic count; written-order vs completion-order results; no fail-fast vs fail-fast.

**How does cancellation work?** A flag plus handlers, propagated to structured children. Code must check it. `onCancel` runs immediately and concurrently.

**`Task.detached`: when is it right?** Almost never. You lose priority, task-locals and actor inheritance. Use a `@concurrent` function, or `Task {}` when you need an unstructured task.

**How do you test a race?** Force the interleaving with a barrier, prove the naive version fails, then show that the fix passes across repeated runs.

**`@Observable` model + long-running `Task`: what leaks?** The task captures `self` until the loop ends. Tie it to `.task {}`, cancel it, or use `[weak self]` inside the loop.

**Why never `DispatchSemaphore` in async code?** It blocks a cooperative-pool thread. Enough of them and the pool deadlocks, because the work that would signal the semaphore can't run.

**`isolated deinit`: when does it run?** Inline if the last release happens on the actor, otherwise enqueued onto it.

**`await` in `defer`: what's the catch?** It runs in the cancelled task. Shield the cleanup if it must finish.

**What does `@preconcurrency import` do?** It downgrades Sendable diagnostics about that module's declarations (to warnings, or silence) until the module adopts concurrency annotations.

**ACP vs MCP (plan context)?** MCP: agent ↔ tools. ACP: editor ↔ agent. Unrelated to Swift concurrency, but on the same interview loop.

---

## 18. Talking points for the platform role

- **Migrations at scale.** "Swift 6 migration is mostly mechanical. The playbook has a rule per diagnostic family, and an agent can apply it file by file with the compiler as the oracle. The non-mechanical parts are the bugs the compiler can't see: reentrancy, leaked tasks, lost cancellation. Those need regression tests the agent must write, and human review gates."
- **Approachable concurrency rollout.** "For app targets I'd turn on default `MainActor` isolation and `NonisolatedNonsendingByDefault` with `swift package migrate`, which adds `@concurrent` where behavior must be preserved. Then I'd measure main-thread hangs before and after, because that setting moves work onto the main actor silently."
- **Determinism as infrastructure.** "Flaky concurrency tests destroy trust in CI and in agent loops: an agent can't fix a test that fails 1 time in 20. So the platform provides gates, barriers and an injected clock, bans `sleep` in tests with a lint rule, and runs new concurrency tests 10× in CI."
- **Hangs are diagnosable.** "When a concurrency test hangs, I don't add a timeout. I `sample` the process. In my BookingSync migration every cooperative thread sat in `queue.sync`, which pointed straight at the store that had been made `@unchecked Sendable` without removing its blocking reads."
- **Verified behavior beats documentation.** "Two examples from my own runs: `withTaskCancellationShield` compiles behind `#available` but crashes the binary at launch on OS 26, and `swiftc -typecheck` doesn't report region-isolation errors. Platform teams find these before 300 engineers do."
