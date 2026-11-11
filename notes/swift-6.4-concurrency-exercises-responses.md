# Swift 6.4 Concurrency in Depth: Responses

Solutions, short theory and interview-drill answers for [swift-6.4-concurrency-exercises.md](swift-6.4-concurrency-exercises.md). The long-form interview theory is in [swift-6.4-language-concurrency.md](swift-6.4-language-concurrency.md). Every solution is real code in this repo, and every claim below was checked against a compiler.

## How this was verified

| What | Result |
| --- | --- |
| Toolchain | **Swift 6.4.2** (swiftly, `.swift-version`) and **Swift 6.3.2** (Xcode 26.5), macOS 26.6, Intel |
| `swift test --filter ConcurrencyTests` on 6.4.2 | **75 tests in 20 suites pass**, **10 runs in a row** |
| `xcrun swift test` on 6.3.2 | **73 tests pass** (the 2 `await`-in-`defer` tests are `#if compiler(>=6.4)`) |
| Warnings | Both new targets build with `.treatAllWarnings(as: .error)` on 6.4: **0 warnings** |
| Compile errors quoted here | **16 new** snippets in [`CompileFailures/C*.swift`](../CompileFailures), all reproduced by [`scripts/verify-compile-errors.sh`](../scripts/verify-compile-errors.sh) (now supports a `// flags:` line). 41/41 overall |
| Tests that sleep | **0**. Coordination uses `AsyncGate`, `AsyncBarrier`, `AsyncStream` and `ManualClock` ([`TestSupport.swift`](../Tests/ConcurrencyTests/TestSupport.swift)) |

## Findings from running real Swift 6.4.2 (read this first)

| # | Finding | Where |
| --- | --- | --- |
| 1 | **Region-isolation errors only appear in a full compile.** `swiftc -typecheck` accepts code that `swift build` rejects with *"sending 'x' risks causing data races"*: the checker is a SIL pass | C06 |
| 2 | **An actor's `let` is implicitly `nonisolated` only inside its module.** From another module (tests included) `inbox.hostID` is *"actor-isolated property 'hostID' can not be referenced from a nonisolated context"*. Spell `nonisolated let` to make it API. The same applies to a `@MainActor` class's `let` | C04, C12 |
| 3 | **A copying initializer keeps the result connected.** `return ReservationDraft(copying: first)` from an actor fails *"task or actor-isolated value cannot be sent"*: an init taking a non-Sendable argument might store it, so the result joins `first`'s region. Copy the Sendable fields out first | C06 |
| 4 | **A `Task` closure can't re-send what it captured.** `Task { await outbox.submit(draft) }` fails even when `draft` is a `sending` parameter *and* `submit` takes `sending`: captures belong to the closure's region (a closure might run twice). Hand the value over directly from an `async` function | C06 |
| 5 | **`await` inside `defer` works in 6.4.2** (SE-0493), and 6.3.2 rejects it (*"'async' call cannot occur in a defer body"*). But the cleanup runs **in the cancelled task**: `Task.isCancelled == true` inside it | C19 |
| 6 | **`withTaskCancellationShield` compiles on 6.4.2 but the binary won't launch on macOS 26**, even behind `if #available(macOS 27, *)`: *dyld: Symbol not found: `_swift_task_cancellationShieldPop`*. The `@_alwaysEmitIntoClient` body strongly references a runtime entry point that only macOS 27 ships. It's compiled only with `-DHAS_TASK_CANCELLATION_SHIELD` | C19 |
| 7 | A function with an `isolated` parameter **can't also be `nonisolated`** (*"global function with 'isolated' parameter cannot be 'nonisolated'"*). Under default `MainActor` isolation that's fine: the `isolated` parameter already overrides the default | C09 |
| 8 | Isolated-conformance errors name the context precisely: *"main actor-isolated conformance of 'X' to 'P' cannot be used in **@concurrent** context"* (from `Task.detached` or a `@concurrent` function) | C07, C09 |
| 9 | `@concurrent` on a synchronous function: *"cannot use @concurrent on non-async global function"* | C10 |
| 10 | Bridging a legacy cancel token: if `cancel()` arrives **before** `start` registers the handler, a naive bridge **hangs forever**. `withTaskCancellationHandler` runs `onCancel` immediately when the task is already cancelled, which is before the operation body. The legacy object must remember "cancelled" | C14 |
| 11 | `isolated deinit` runs **inline** when the last release happens on the main actor, and is **enqueued** when it happens elsewhere (verified both ways) | C12 |
| 12 | `Observations` is transactional: three synchronous mutations in one turn produce **one** value (the last) | C16 |
| 13 | `Task {}` and task-group children copy task-locals; `Task.detached` starts with none. An `async let` created in a cancelled task is cancelled; `Task {}` and `Task.detached` aren't | C14, C18 |
| 14 | A plain `nonisolated async` function called from `@MainActor` runs **off** the main thread under Swift 6 defaults, and **on** it with `NonisolatedNonsendingByDefault` (checked with both `#isolation` and `pthread_main_np()`) | C08, C10 |
| 15 | **Pool starvation, found by a test** (BookingSync capstone): a `queue.sync` reader-writer store wrapped in `@unchecked Sendable` compiles, and **deadlocks** with 20 parallel test cases. `sample` showed 16/16 cooperative threads in `_dispatch_sync_f_slow` behind a barrier that never got a thread. Fixed with `OSAllocatedUnfairLock` | Capstone |
| 16 | `swift package migrate --to-feature NonisolatedNonsendingByDefault` (6.4.2) updates the manifest and adds `@concurrent` to every `nonisolated async` function whose behavior would change, **including protocol requirements**. Pruning those is a manual step | Capstone |

### Code map

| Exercise | Solution | Tests |
| --- | --- | --- |
| C01–C04 | [`Sources/Concurrency/C01…C04_*.swift`](../Sources/Concurrency) | [`IsolationTests.swift`](../Tests/ConcurrencyTests/IsolationTests.swift) |
| C05–C08 | [`Sources/Concurrency/C05…C08_*.swift`](../Sources/Concurrency) | [`DataRaceSafetyTests.swift`](../Tests/ConcurrencyTests/DataRaceSafetyTests.swift) |
| C09–C12 | [`Sources/ConcurrencyApp/`](../Sources/ConcurrencyApp) | [`ApproachableConcurrencyTests.swift`](../Tests/ConcurrencyTests/ApproachableConcurrencyTests.swift) |
| C13–C16 | [`Sources/Concurrency/C13…C16_*.swift`](../Sources/Concurrency) | [`StructuredConcurrencyTests.swift`](../Tests/ConcurrencyTests/StructuredConcurrencyTests.swift) |
| C17–C20 | [`Sources/Concurrency/C17…C20_*.swift`](../Sources/Concurrency) | [`DeterminismTests.swift`](../Tests/ConcurrencyTests/DeterminismTests.swift) |
| Compile errors | [`CompileFailures/C*.swift`](../CompileFailures) | `scripts/verify-compile-errors.sh` |
| Capstone | `swiftmigrator/fixtures/{before,after}/BookingSync` | `swift test` in `after/BookingSync` |

---

# Tier 1: Isolation

## C01. Isolation domains

**Theory.** Code runs in exactly one isolation domain: an **actor instance** (each instance is separate), a **global actor** (one domain shared by everything annotated with it), or **nonisolated**. Crossing domains is always an `await`. Synchronous code never changes domains: it runs wherever its caller runs.

**Solution:** [C01_IsolationDomains.swift](../Sources/Concurrency/C01_IsolationDomains.swift)

```swift
package func isolationLabel(_ isolation: isolated (any Actor)? = #isolation) -> String {
    guard let isolation else { return "nonisolated" }
    if isolation === MainActor.shared { return "MainActor" }
    return String(describing: type(of: isolation))
}
```

The tests prove: an actor method reports `PriceCalendar`; a *synchronous* nonisolated helper called from that method reports `PriceCalendar` too (no hop); a `@MainActor` test reports `MainActor`; a plain async test reports `nonisolated`; copying between two calendars requires `await` even though they're the same type.

**Interview drill**
- **Isolation domain.** A region of code and state that's guaranteed to be accessed by one task at a time. Three kinds: an actor instance, a global actor (`@MainActor` or your own), and nonisolated (no protection, so only `Sendable` state can be touched).
- **Does sync nonisolated code hop?** No. Only `async` calls can switch executors. A sync function inherits whatever executor its caller is on, which is why it can't touch actor state (it might not be on the actor).
- **`#isolation`.** A macro that expands to the isolation of the code where it's *written*. As a default argument it's evaluated at the call site, so `func f(isolation: isolated (any Actor)? = #isolation)` runs on the caller's actor without the caller writing anything.

---

## C02. Global actors

**Theory.** `@globalActor` gives a singleton actor a name you can use as an attribute. Everything annotated with it shares one serial executor, so calls between them are synchronous. Global-actor-isolated types are implicitly `Sendable`, because the actor protects their state.

**Solution:** [C02_GlobalActors.swift](../Sources/Concurrency/C02_GlobalActors.swift)

```swift
@globalActor package actor SyncActor { package static let shared = SyncActor() }

@SyncActor package final class SyncSession {
    package func run(listingIDs: [Int]) -> Int {
        for id in listingIDs { journal.append("synced \(id)") }   // same domain: no await
        return journal.entries.count
    }
}

notifier.notify {                       // documented: always called on the main queue
    MainActor.assumeIsolated { self.increment() }
    done()
}
```

**Interview drill**
- **Why implicitly `Sendable`?** Every access to its state is serialized by the global actor, so sharing the *reference* across domains is safe: other domains must `await` to touch it.
- **`assumeIsolated` vs `MainActor.run`.** `assumeIsolated` is synchronous and free (no hop, no suspension). It checks the executor at runtime and **traps** if wrong. `await MainActor.run` always works, but it's async, so it can't be used from a synchronous callback, and it changes ordering. Use `assumeIsolated` only when an API contract guarantees the thread (main-queue callbacks, `UIView` methods).
- **Custom global actor vs `actor` type.** When a subsystem's state is spread across several types and free functions that need to call each other synchronously (a database layer, a sync engine). An `actor` type isolates one object; a global actor isolates a *module slice*.

---

## C03. Reentrancy

**Theory.** Actors guarantee one task at a time *between suspension points*, not for a whole method. At each `await` the actor can run other calls. So any invariant read before an `await` may be stale after it. The compiler can't detect this: it's a logic bug, not a data race.

**Solution:** [C03_Reentrancy.swift](../Sources/Concurrency/C03_Reentrancy.swift)

```swift
// ✅ dedup: record the work before suspending
if let running = inFlight[listingID] { joinedInFlight += 1; return try await running.value }
let task = Task { try await fetch(listingID) }
inFlight[listingID] = task
defer { inFlight[listingID] = nil }
let fresh = try await task.value

// ✅ hold: mutate synchronously before the await, roll back on failure
guard booked.isDisjoint(with: nights) else { throw .nightsUnavailable }
booked.formUnion(nights)
do { try await authorize(guest) } catch { booked.subtract(nights); throw .paymentDeclined }
```

The tests *prove the bugs first*: with an `AsyncBarrier(count: 5)` inside the fetch, the naive cache provably makes 5 fetches (the barrier only opens when all 5 are inside). With a barrier of 2 in the payment step, the naive desk sells the same nights twice. The fixed versions: 1 fetch for 5 callers (`joinedInFlight == 4`), and exactly 1 of 3 guests books, in 20 parameterized runs.

**Interview drill**
- **Why reentrant?** Non-reentrant actors deadlock: actor A awaits B, which awaits A. They also block every other caller during slow I/O (priority inversion, poor throughput). Reentrancy trades deadlocks for interleavings, which you can reason about locally.
- **Review rule.** "Inside an actor, no decision may be based on state read before an `await`. Either finish the read-modify-write synchronously, record intent (in-flight task, hold) before suspending, or re-validate after."
- **Why `defer` on the in-flight entry?** If the fetch throws, a stale entry would make every future caller await a failed task forever (it caches the error). `defer` removes it on both paths.

---

## C04. `nonisolated` and `isolated` parameters

**Theory.** `nonisolated` exempts a member from the actor: it's callable synchronously from anywhere, and it may only touch immutable `Sendable` state. An `isolated` parameter puts the function *on* the argument's actor: inside, every member is synchronous. One hop instead of one per call, and no interleaving between the steps.

**Solution:** [C04_NonisolatedAndIsolatedParameters.swift](../Sources/Concurrency/C04_NonisolatedAndIsolatedParameters.swift)

```swift
package nonisolated let hostID: Int        // ⚙️ explicit: implicit nonisolation is module-local
package nonisolated func hash(into hasher: inout Hasher) { hasher.combine(hostID) }

package func triage(_ inbox: isolated HostInbox, keepingLast n: Int) -> Int {
    inbox.markAllRead(); inbox.archive(keepingLast: n); return inbox.count
}
```

**Interview drill**
- **Why `nonisolated hash(into:)`?** `Hashable`'s requirements are synchronous and nonisolated: `Set` calls them from whatever context it's in. An actor-isolated witness would need an `await`. Base hashing on immutable `let`s.
- **N awaits vs an `isolated` parameter.** N awaits = N potential suspension points, where other callers can interleave and see half-done state. One `isolated` function = one hop and an atomic sequence (as long as it doesn't `await` inside).
- **`nonisolated` reading a `var`/`let`.** A `var`: no (that's the data race the actor prevents). A `let` of a `Sendable` type: yes. ⚙️ Implicitly only within the module; across modules it must be declared `nonisolated let`.

---

# Tier 2: Data-race safety

## C05. The Sendable ladder and `Mutex`

**Theory.** `Sendable` = safe to share across isolation domains. The safest rung that fits wins: value type → immutable final class → isolation (actor / global actor) → `Mutex` → `@unchecked Sendable`.

**Solution:** [C05_SendableAndMutex.swift](../Sources/Concurrency/C05_SendableAndMutex.swift)

```swift
package final class RateLimiter: Sendable {
    private let state: Mutex<State>                  // the state lives *inside* the lock
    package func tryAcquire() -> Bool {
        state.withLock { s in guard s.tokens > 0 else { s.rejected += 1; return false }
                              s.tokens -= 1; s.granted += 1; return true }
    }
}
```

Compile errors reproduced: *"stored property 'tokens' of 'Sendable'-conforming class 'RateLimiter' is mutable"*, *"non-final class 'ExchangeRates' cannot conform to the 'Sendable' protocol"*, *"mutation of captured var 'count' in concurrently-executing code"*, *"…is not concurrency-safe because it is nonisolated global shared mutable state"*.

**Interview drill**
- **Why `final`?** A subclass could add mutable state and break the guarantee, and the compiler can't check subclasses it doesn't see.
- **`Mutex` vs actor.** `Mutex`: synchronous, tiny critical sections, callable from sync code (counters, caches, rate limiters); you must never `await` while holding it (and `withLock`'s closure is synchronous, so you can't). Actor: async access, longer operations, you need to call async things while keeping ownership of state. Rule of thumb: if callers can't be `async`, it's a `Mutex`.
- **`@unchecked` acceptance criteria.** Name the lock or queue that guards *every* mutable property, in a comment next to the conformance. Prefer converting to `Mutex`. Add a removal condition. It's a promise the compiler stops checking forever, so it's reviewed like `unsafe` code.

---

## C06. Regions and `sending`

**Theory.** Region-based isolation (SE-0414) groups values that might reference each other into *regions*. A region not reachable from any actor or task is **disconnected** and can be *transferred* across a boundary, even if its type isn't `Sendable`. After the transfer, using it from the old side is an error. `sending` (SE-0430) is that requirement in a signature: a `sending` parameter is disconnected on entry; a `sending` result is disconnected on return.

**Solution:** [C06_RegionsAndSending.swift](../Sources/Concurrency/C06_RegionsAndSending.swift)

```swift
package func makeDraft(…) -> sending ReservationDraft { … }         // fresh object

package func forward(_ draft: sending ReservationDraft, to outbox: ReservationOutbox) async {
    await outbox.submit(draft)                                       // ✅ disconnected, so transferable
}

package func exportFirst() -> sending ReservationDraft? {            // inside the actor
    guard let first = pending.first else { return nil }
    let (listingID, nights, notes) = (first.listingID, first.nights, first.notes)   // Sendable values
    let copy = ReservationDraft(listingID: listingID, nights: nights); copy.notes = notes
    return copy                                                       // ✅ new region
}
```

Findings 1, 3 and 4 above all came from this exercise.

**Interview drill**
- **Region.** A set of non-Sendable values that may alias. Regions merge when values get connected: stored into each other, passed together to a function, or captured by the same closure. Actor-isolated state is one permanent region.
- **`Sendable` vs `sending`.** `Sendable` is a property of a *type* ("always safe to share"). `sending` is a property of a *value at one point* ("nobody else holds this right now"). `sending` lets non-Sendable types move between domains, as in a builder pattern or a freshly decoded model.
- **Why does `Task.init` take a `sending` closure?** So non-Sendable state can be *moved* into a task (the caller gives it up), which `@Sendable` would forbid. The trade-off is finding 4: the captured values belong to that closure from then on.

---

## C07. Isolated conformances

**Theory.** Before Swift 6.2, a `@MainActor` type conforming to a nonisolated protocol had three bad options: make the witnesses `nonisolated` (they lose access to state), `@preconcurrency` the conformance (runtime checks, crashes if wrong), or isolate the whole protocol (contaminates every conformer). SE-0470 adds `extension T: @MainActor P`: the conformance exists only on the main actor, and the compiler stops you from using it elsewhere.

**Solution:** [C07_IsolatedConformances.swift](../Sources/Concurrency/C07_IsolatedConformances.swift)

```swift
extension ListingCardModel: @MainActor PriceDisplaying {
    package func displayPrice() -> String { "\(nightlyCents / 100) \(currency)/night" }   // reads state
}
```

Errors reproduced: without the attribute, *"conformance of 'ListingCardModel' to protocol 'PriceDisplaying' crosses into main actor-isolated code and can cause data races"* (with three fix-its: isolate the conformance, `@preconcurrency`, or `nonisolated` everything). Using it from `Task.detached`: *"main actor-isolated conformance … cannot be used in @concurrent context"*.

**Interview drill**
- **Pre-6.2 options and cost.** `nonisolated` witnesses (no state access, often useless), `@preconcurrency` conformance (dynamic checks, crash when violated), `@MainActor protocol` (forces isolation on everyone, breaks non-UI conformers).
- **Why can a nonisolated sync generic use it?** A synchronous nonisolated function runs on its caller's executor. Called from the main actor, it *is* on the main actor, so the compiler allows the isolated conformance there. An async or `@concurrent` function would move off it.
- **`InferIsolatedConformances`.** In a default-`MainActor` module, conformances of main-actor types are inferred to be `@MainActor` isolated automatically. That's why a DTO must be explicitly `nonisolated` to decode in the background (C09).

---

## C08. Isolation-inheriting helpers

**Theory.** Under Swift 6 defaults (SE-0338), a `nonisolated async` function runs on the global executor. So a generic helper's closure parameter crosses a boundary every time, and it must be `@Sendable`, which callers on an actor can't satisfy when they capture their own state. Fix it by making the helper run on the caller: `isolated (any Actor)? = #isolation` (6.0) or `nonisolated(nonsending)` (6.2).

**Solution:** [C08_IsolationInheritingHelpers.swift](../Sources/Concurrency/C08_IsolationInheritingHelpers.swift)

```swift
package func withRetry<T>(attempts: Int, isolation: isolated (any Actor)? = #isolation,
                          _ operation: () async throws -> T) async throws -> T

nonisolated(nonsending)
package func withRetryNonsending<T>(attempts: Int,
                                    _ operation: nonisolated(nonsending) () async throws -> T) async throws -> T
```

The `@MainActor` tests pass closures that mutate a **non-Sendable** class and return non-Sendable results. `nonsendingLabel()` reports `MainActor`, `plainNonisolatedLabel()` reports `nonisolated`. `JobQueue` reads `job.isolation` synchronously (`MainActor`, `SyncActor`, nil).

**Interview drill**
- **Why is the plain helper rejected?** It runs on the global executor, so its closure would run concurrently with the main actor while capturing main-actor state. That would be a data race, so the closure must be `@Sendable`, and a closure capturing a non-Sendable class can't be.
- **`isolated` vs `nonisolated(nonsending)`.** Same runtime semantics (run on the caller's executor). `nonisolated(nonsending)` doesn't add a parameter and composes with function types. For a library supporting Swift 6.0/6.1 clients, use the `#isolation` parameter (the stdlib does: `withTaskGroup(…, isolation:)`).
- **`@isolated(any)`.** It lets a function value carry its isolation dynamically (`f.isolation`). `Task.init` uses it to enqueue a `{ @MainActor in … }` closure *directly* on the main actor, with no hop through the global executor first, which also preserves ordering.

---

# Tier 3: Approachable concurrency

## C09. Default `MainActor` isolation

**Theory.** `.defaultIsolation(MainActor.self)` (SE-0466; `-default-isolation MainActor`) makes every unannotated declaration in the module `@MainActor`. Most app code is UI code, so this removes most annotations *and* most Sendable errors (everything is in one domain). You opt out with `nonisolated` on types and functions that must run anywhere.

**Solution:** [C09_DefaultMainActorIsolation.swift](../Sources/ConcurrencyApp/C09_DefaultMainActorIsolation.swift)

```swift
package final class SearchModel { … }                   // @MainActor, so Sendable, with no annotation
nonisolated package struct ListingDTO: Decodable, Sendable, Equatable { … }   // must decode anywhere
```

Errors reproduced: *"main actor-isolated property 'query' can not be mutated from a nonisolated context"*; a DTO without `nonisolated` decoded in `@concurrent`: *"main actor-isolated conformance of 'ListingDTO' to 'Decodable' cannot be used in @concurrent context"*.

**Interview drill**
- **Which targets?** App targets and UI feature modules: yes. Libraries, networking, persistence, parsing and SDK packages: no (they're used from everywhere, and `MainActor` would be a contagious API decision). That's why SwiftPM's default stays nonisolated and Xcode turns it on only for new app targets.
- **Why does the DTO break?** In that module the `Decodable` conformance is inferred to be main-actor isolated (`InferIsolatedConformances`), so `JSONDecoder` can't use it off the main actor. `nonisolated struct` makes the type and its conformances nonisolated.
- **"Approachable Concurrency" setting.** `SWIFT_APPROACHABLE_CONCURRENCY` enables the upcoming features `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `InferSendableFromCaptures`, `GlobalActorIsolatedTypesUsability` and `DisableOutwardActorInference` (the last three are already on in Swift 6 mode). Default `MainActor` isolation is a separate setting (`SWIFT_DEFAULT_ACTOR_ISOLATION`), also on by default for new app targets.

---

## C10. `nonisolated(nonsending)` vs `@concurrent`

**Theory.** SE-0338 (Swift 5.7) said `nonisolated async` functions always run on the global executor. That surprised people: the same function ran on the main thread when synchronous and off it when `async`, and every non-Sendable argument crossed a boundary. SE-0461 (6.2) makes `nonisolated async` mean "run on the caller's actor" (`nonisolated(nonsending)`) under `NonisolatedNonsendingByDefault`, and adds `@concurrent` for "always run on the global executor".

**Solution:** [C10_NonsendingVsConcurrent.swift](../Sources/ConcurrencyApp/C10_NonsendingVsConcurrent.swift). From a `@MainActor` test: `inheritsCaller() == true`, `alwaysOffActor() == false`, and `pthread_main_np()` agrees.

**Interview drill**
- **SE-0338 semantics.** `nonisolated async` = hop to the global concurrent executor. It was good for not blocking the main actor by accident, and bad for Sendable friction and surprise.
- **Migration regression.** Code that *relied on* hopping off (JSON decoding, image resizing in a `nonisolated async` func called from the main actor) now runs **on the main actor**, which shows up as hangs and hitches, not compile errors. Find candidates with `swift package migrate --to-feature NonisolatedNonsendingByDefault`: it adds `@concurrent` to keep the old behavior. Then profile with the Swift Concurrency instrument and remove `@concurrent` where hopping wasn't needed.
- **`@concurrent` on sync?** No: *"cannot use @concurrent on non-async global function"*. Sync code can't switch executors.

---

## C11. Offloading work

**Theory.** In a main-actor-by-default module, anything expensive must be marked `@concurrent`, and everything it touches must be nonisolated and `Sendable` (inputs and outputs cross the boundary).

**Solution:** [C11_OffloadingWork.swift](../Sources/ConcurrencyApp/C11_OffloadingWork.swift)

```swift
nonisolated package enum ListingDecoder {
    @concurrent package static func decode(_ data: Data) async throws -> [ListingDTO] { … }
}
// SearchLoader (main actor by default)
let dtos = try await ListingDecoder.decode(payload)   // off the main actor
model.update(query: query, results: dtos)            // back on it, with no DispatchQueue
```

**Interview drill**
- **What each inherits.**

  | | Actor | Priority | Task-locals | Cancellation | Structured |
  | --- | --- | --- | --- | --- | --- |
  | `@concurrent` function | no (global executor) | yes | yes | yes | **yes**, it's just a call |
  | `Task {}` | yes | yes | yes | no | no |
  | `Task.detached {}` | no | no | no | no | no |
  | `DispatchQueue.global().async` | no | QoS only | no | no | no |

- **Structured?** Only `@concurrent`: the caller awaits it, and cancellation propagates. Prefer it over detached tasks.

---

## C12. `isolated deinit` and `Task.immediate`

**Theory.** A regular `deinit` runs on whatever thread drops the last reference, so it's always nonisolated, even on a `@MainActor` class (error: *"call to main actor-isolated global function 'unregister' in a synchronous nonisolated context"*). `isolated deinit` (SE-0371) runs on the actor: inline if the last release happens there, otherwise enqueued. `Task.immediate` (SE-0472) starts running synchronously in the caller's context until its first real suspension; `Task {}` is only enqueued.

**Solution:** [C12_IsolatedDeinitAndImmediateTasks.swift](../Sources/ConcurrencyApp/C12_IsolatedDeinitAndImmediateTasks.swift). Tests verify inline vs enqueued `deinit`, and that right after `startImmediate()` the log already holds `"immediate: started"`, while after `startEnqueued()` it's empty.

**Interview drill**
- **Why nonisolated `deinit`?** The last release can happen on any thread, and `deinit` is synchronous, so it can't hop.
- **Inline vs enqueued.** Inline when the releasing code is already on the actor. Otherwise enqueued: the object is destroyed *later*, so code that expects cleanup to have happened ("the registry is empty now") can race. Never write code whose correctness depends on `deinit` timing.
- **UI case for `Task.immediate`.** A button handler that sets `isLoading = true` and starts a fetch: with `Task {}` the spinner appears a frame late (or a second tap gets through). With `Task.immediate` the state change happens synchronously before the handler returns. Same for "cancel the previous search task and start a new one" ordering.

---

# Tier 4: Structured concurrency

## C13. `async let` vs task groups

**Theory.** Both create child tasks that can't outlive the scope. `async let`: a fixed number of children, possibly with different types, awaited **in the order you write**. Task group: a dynamic number of children of one type, results **in completion order**. Leaving either scope cancels unfinished children and waits for them.

**Solution:** [C13_AsyncLetAndTaskGroups.swift](../Sources/Concurrency/C13_AsyncLetAndTaskGroups.swift)

```swift
// hedged request
for mirror in mirrors { group.addTask { try? await mirror() } }
while let result = try await group.next() {
    if let value = result { group.cancelAll(); return value }
}
throw QuoteError.noMirrorResponded
```

Tests: with `async let`, `fees` fails immediately but the error surfaces only after `nightly` (gated) completes. With the group, `fees` fails and `nightly` observes cancellation.

**Interview drill**
- **Unawaited `async let`?** It's implicitly cancelled and *awaited* at scope exit. It never leaks, but the scope doesn't end until it finishes cancelling.
- **Why wait for cancelled children?** Structured concurrency guarantees that children never outlive the parent. That makes resource lifetimes, task-locals and error propagation sound.
- **First of N wins:** the code above. Note `try?` so one failing mirror doesn't end the group, and `cancelAll()` before returning.

---

## C14. Cancellation

**Theory.** `task.cancel()` sets a flag on the task and its structured children and runs registered cancellation handlers. Nothing stops by itself: code polls `Task.isCancelled` / `try Task.checkCancellation()`, or registers `withTaskCancellationHandler` to forward cancellation to a legacy API.

**Solution:** [C14_Cancellation.swift](../Sources/Concurrency/C14_Cancellation.swift)

```swift
try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { c in start { c.resume(with: $0) } }
} onCancel: {
    cancel()          // may run *before* start(): LegacyDownload remembers it (finding 10)
}
```

**Interview drill**
- **`isCancelled` vs `checkCancellation`.** `checkCancellation` throws `CancellationError`: use it when partial work is worthless. `isCancelled`: use it to stop early and return a partial result (the importer).
- **When does `onCancel` run?** Immediately, synchronously, on the cancelling thread, concurrently with the operation. If the task is already cancelled, before the operation starts. So it must be `@Sendable` and thread-safe.
- **`Task {}` and cancellation.** It's unstructured: nobody owns it, so there's nothing to inherit cancellation *from*. That's useful for shields and fire-and-forget work, and a trap when a view model starts `Task {}` in `onAppear` and the work keeps running after the screen is gone. Store the task and cancel it, or use `.task {}`.

---

## C15. `AsyncStream`

**Theory.** `AsyncStream.makeStream` gives a stream and a continuation. The producer calls `yield`/`finish`, and `onTermination` runs when the consumer stops (cancellation, finish, or dropping the stream). The buffering policy decides what happens when the producer is faster.

**Solution:** [C15_AsyncStream.swift](../Sources/Concurrency/C15_AsyncStream.swift)

```swift
let (stream, continuation) = AsyncStream.makeStream(of: AvailabilityChange.self, bufferingPolicy: policy)
let token = addObserver { continuation.yield($0) }
continuation.onTermination = { [weak self] _ in self?.removeObserver(token) }
```

**Interview drill**
- **Buffering.** Progress bar: `.bufferingNewest(1)` (only the latest matters). Event log or analytics: `.unbounded`, or a large `.bufferingOldest(n)` if memory must be bounded and you accept dropping. Location feed: `.bufferingNewest(1)`.
- **Two consumers?** `AsyncStream` is unicast: elements are split between iterators, not duplicated. For broadcast, create one stream per subscriber (as `changes()` does).
- **Forgetting `onTermination`** leaks the observer closure (and the continuation in it) inside the client for its whole lifetime, and keeps the producer doing work for nobody.

---

## C16. Custom `AsyncSequence` and `Observations`

**Theory.** SE-0421 added a `Failure` associated type and `next(isolation:)` to `AsyncIteratorProtocol`, so operators can preserve "doesn't throw" and run on the caller's actor without hopping. `Observations` (SE-0475) turns any `@Observable` reads into an `AsyncSequence` of values, emitting transactionally.

**Solution:** [C16_AsyncSequencesAndObservations.swift](../Sources/Concurrency/C16_AsyncSequencesAndObservations.swift)

```swift
package mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
    while let element = try await base.next(isolation: actor) {
        if element != last { last = element; return element }
    }
    return nil
}
```

**Interview drill**
- **Why SE-0421?** Before it, every custom `AsyncSequence` iterator's `next()` was `throws` (callers wrote `try` for non-throwing streams). Being nonisolated async, it also hopped to the global executor on every element, which made non-Sendable elements impossible.
- **`Observations` vs `withObservationTracking` vs `@Published`.** `withObservationTracking` fires `onChange` once (willSet, before the value changes) and must be re-registered. `Observations` is the async-sequence version: it re-tracks automatically, delivers the *new* value and coalesces changes in a transaction. `@Published` is Combine and `ObservableObject`, the pre-Observation world.

---

# Tier 5: Determinism and Swift 6.4

## C17. Injected clocks

**Theory.** Time is a dependency. Code that waits takes `some Clock<Duration>`; production passes `ContinuousClock()`, tests pass a `ManualClock` and advance it explicitly. The hard part is synchronization: the test must know the code is *already sleeping* before it advances (`waitForSleepers`), or the test races the code.

**Solution:** [C17_InjectedClocks.swift](../Sources/Concurrency/C17_InjectedClocks.swift). `ManualClock` keeps sleepers in a `Mutex`. Its `sleep` is wrapped in `withTaskCancellationHandler`, and it remembers IDs cancelled before registration (the same race as finding 10).

**Interview drill**
- **`Task.sleep` in tests.** It's slow and flaky: too short fails on loaded CI, too long wastes minutes across a suite. The alternative is an injected clock plus explicit synchronization, so the test proves an ordering instead of hoping for one.
- **Cancelled before registering.** Remember the cancelled ID and resume with `CancellationError` when the sleeper registers. Otherwise it sleeps forever.

---

## C18. Task-locals and priority

**Theory.** `@TaskLocal` values are bound for a scope (`$x.withValue(v) { … }`) and inherited by child tasks and `Task {}`, not by `Task.detached`. Priority: children inherit it; a higher-priority task awaiting a lower-priority one **escalates** it automatically. SE-0462 (6.2) lets code observe (`withTaskPriorityEscalationHandler`) and trigger (`task.escalatePriority(to:)`) escalation.

**Interview drill**
- **Good for:** tracing IDs, logging context, test overrides of dependencies. **Bad for:** anything that should be an explicit parameter (business inputs). They're invisible in signatures and silently missing in detached tasks.
- **Priority inversion.** Awaiting a task's value, or an actor running a job on behalf of a higher-priority waiter, raises the priority of the awaited work. The escalation handler lets you forward that to things the runtime can't see (a `URLSessionTask`'s priority).

---

## C19. Async cleanup

**Theory.** Cleanup has two requirements: it must run on every exit path, and it must be able to finish when the task is cancelled. Swift 6.4's `defer { await … }` solves the first. A cancellation shield solves the second. Until a deployment target has `withTaskCancellationShield` (macOS/iOS 27), an unstructured task is the portable shield.

**Solution:** [C19_AsyncCleanup.swift](../Sources/Concurrency/C19_AsyncCleanup.swift)

```swift
#if compiler(>=6.4)
package func syncReleasingInShieldedDefer(_ lease: SyncLease, work: @Sendable () async throws -> Void) async throws {
    defer { await shielded { await lease.release() } }     // always runs, and finishes un-cancelled
    try await work()
}
#endif
```

Tests: with a plain `defer`, `releaseSawCancellation == true`; with the shielded `defer`, `false`.

**Interview drill**
- **Why `defer` isn't enough.** It runs, but inside the cancelled task: a `URLSession` call or `Task.sleep` in the cleanup throws `CancellationError` immediately, so the server lease is never released.
- **Why a dedicated shield?** `Task {}` allocates a task, hops executors, loses the structured relationship (no priority propagation back, a new task-local copy) and needs `@Sendable` captures. A shield keeps the same task and only hides the flag for a scope.

---

## C20. Bounded and discarding groups

**Theory.** A task group doesn't limit concurrency: `addTask` 100,000 times creates 100,000 tasks (memory, sockets and server load all at once). Bound it by seeding N tasks and adding one as each finishes. A discarding group never stores results, so its memory stays flat for long-running loops.

**Solution:** [C20_BoundedAndDiscardingGroups.swift](../Sources/Concurrency/C20_BoundedAndDiscardingGroups.swift). The gauge test (`@Test(arguments: [1, 3, 8])`) proves the peak is ≤ the limit and that results keep input order.

**Interview drill**
- **100,000 `addTask`s.** Each task costs memory, and each upload opens a connection. You get file-descriptor exhaustion, server rate limits and a memory spike. And results pile up in the group.
- **Discarding group.** Server-style loops (accept connections, handle webhook events) where children report through side effects. With a regular group, unread results would accumulate forever.

---

# Capstone: BookingSync

See `swiftmigrator/fixtures/before/BookingSync/MIGRATION_TASKS.md` for the planted issues and `swiftmigrator/playbook/MIGRATION_PLAYBOOK.md` (v2) for the rules applied. The appendix of the playbook maps every BookingSync file to the rules used.
