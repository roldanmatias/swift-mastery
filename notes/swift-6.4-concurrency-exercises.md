# Swift 6.4 Concurrency in Depth: 20 Exercises + Capstone

- Solutions, theory and drill answers: [swift-6.4-concurrency-exercises-responses.md](swift-6.4-concurrency-exercises-responses.md)
- Interview theory (read this first): [swift-6.4-language-concurrency.md](swift-6.4-language-concurrency.md)

## How to use this file

For every exercise:

1. **Read first.** Open the linked proposal or WWDC session.
2. **Predict.** Before compiling, write down (a) where each line runs (which isolation domain) and (b) which diagnostic you expect. Concurrency is the topic where intuition fails most often.
3. **Paste real diagnostics.** Ask the Xcode agent: *"Explain this diagnostic: what region/isolation reasoning produced it? Don't give me the fix."*
4. **Prove it with tests.** Swift Testing. **No `sleep` in any test**: coordinate with gates, barriers, `AsyncStream`s and an injected clock.
5. **Run it 10 times.** `for i in $(seq 10); do swift test --filter ConcurrencyTests; done`. Concurrency bugs are flaky; one green run proves little.
6. **Drill.** Answer each interview question out loud in under 90 seconds.

> ⚙️ **Full builds only.** Region-isolation diagnostics (`sending '…' risks causing data races`) come from a SIL pass. `swiftc -typecheck` doesn't show them. Use `swift build` or `scripts/verify-compile-errors.sh`.

### Package layout

```
Sources/
├── Concurrency/       // C01–C08, C13–C20 — Swift 6 defaults (nonisolated by default)
└── ConcurrencyApp/    // C09–C12 — "Approachable Concurrency":
                       //   .defaultIsolation(MainActor.self)
                       //   .enableUpcomingFeature("NonisolatedNonsendingByDefault")
                       //   .enableUpcomingFeature("InferIsolatedConformances")
Tests/ConcurrencyTests/ // TestSupport.swift (Counter, Flag, AsyncGate, AsyncBarrier, suspendUntilCancelled)
CompileFailures/C*.swift // every "this doesn't compile" claim, checked by scripts/verify-compile-errors.sh
```

Two targets on purpose: the same code means different things under the two settings, and being able to say *which* setting a codebase uses is a senior-level signal.

### Coverage map

| Area | Exercises |
| --- | --- |
| Isolation | C01 isolation domains & `#isolation` · C02 global actors & `assumeIsolated` · C03 reentrancy · C04 `nonisolated` & `isolated` parameters |
| Data-race safety | C05 `Sendable` ladder & `Mutex` · C06 regions & `sending` · C07 isolated conformances · C08 isolation-inheriting helpers & `@isolated(any)` |
| Approachable concurrency (6.2+) | C09 default `MainActor` isolation · C10 `nonisolated(nonsending)` vs `@concurrent` · C11 offloading work · C12 `isolated deinit` & `Task.immediate` |
| Structured concurrency | C13 `async let` vs task groups · C14 cancellation · C15 `AsyncStream` · C16 custom `AsyncSequence` & `Observations` |
| Determinism and 6.4 | C17 injected clocks · C18 task-locals & priority escalation · C19 async cleanup (`await` in `defer`, shields) · C20 bounded & discarding groups |
| Capstone | BookingSync: migrate a harder module by hand (in `swiftmigrator`) |

| Level | Meaning |
| --- | --- |
| L2 | Requires reasoning about where code runs |
| L3 | Requires reasoning about regions, interleavings or ordering |
| L4 | Easy to get subtly wrong even when it compiles |

**Shared domain:** the same Airbnb-style booking domain (listings, availability, reservations, hosts, payments).

---

# Tier 1: Isolation

## C01. Isolation domains and `#isolation` (L2)

**Concept:** there are three kinds of isolation domain: an actor *instance*, a *global* actor and *nonisolated*. Every line of code runs in exactly one.

**Task.**
1. Write `isolationLabel(_ isolation: isolated (any Actor)? = #isolation) -> String` returning `"nonisolated"`, `"MainActor"` or the actor's type name.
2. Write `actor PriceCalendar` (day → price) with `whereAmI()`, `copyPrices(from:days:)` and `isSameDomain(as:)`.
3. Write a **synchronous** nonisolated helper and call it from inside the actor. Predict its label first.

**Tests**
- `actorMethodsRunOnTheActor`, `synchronousHelperRunsWhereItsCallerRuns`
- `mainActorCode` (a `@MainActor @Test`), `nonisolatedTestHasNoActor`
- `everyActorInstanceIsItsOwnDomain`: copying between two `PriceCalendar`s needs `await`

**Interview drill**
- What is an isolation domain? Name the three kinds.
- Does a synchronous nonisolated function called from an actor hop off the actor?
- What does `#isolation` expand to, and why is it useful as a *default argument*?

<details><summary>Hints</summary>

- An `isolated` parameter makes the function run *on* that actor; `#isolation` is evaluated at the call site.
- Synchronous code never hops. Only `async` functions can change executors.
</details>

**Read first:** [SE-0306 Actors](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md), [SE-0420 Inheritance of actor isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md).

---

## C02. Global actors and `MainActor.assumeIsolated` (L2)

**Concept:** a global actor is one shared domain for many declarations. `assumeIsolated` asserts isolation at runtime instead of hopping.

**Task.**
1. Declare `@globalActor actor SyncActor`. Put two classes on it (`SyncJournal`, `SyncSession`) that call each other **without `await`**.
2. Wrap a legacy `LegacyMainQueueNotifier` (calls back on `DispatchQueue.main`) and update a `@MainActor BadgeModel` from that callback using `MainActor.assumeIsolated`.

**Constraints:** no `Task { @MainActor in … }` inside the callback (it changes ordering).

**Tests:** same-domain calls; `globalActorIsolatedClassesAreSendable` (use one from `Task.detached`); `assumeIsolatedOnAKnownMainQueueCallback`.

**Interview drill**
- Why is a global-actor-isolated class implicitly `Sendable`?
- `assumeIsolated` vs `await MainActor.run`: what does each cost, and what happens when the assumption is wrong?
- When would you create a custom global actor instead of an `actor` type?

**Read first:** [SE-0316 Global actors](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0316-global-actors.md), [SE-0392 Custom actor executors](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0392-custom-actor-executors.md) (`assumeIsolated`).

---

## C03. Actor reentrancy: duplicate work and double booking (L3)

**Concept:** actors serialize *access*, not *operations*. Every `await` inside an actor lets other calls run. The compiler can't see these bugs.

**Task.**
1. `actor AvailabilityCache`: write `availabilityNaive(for:)` (check cache → `await fetch` → store) and prove that 5 concurrent callers trigger 5 fetches. Then write `availability(for:)` that deduplicates with an in-flight `Task` dictionary.
2. `actor ReservationDesk`: write `bookNaive` (check availability → `await authorize` payment → book) and prove two guests can book the same nights. Then fix it with a synchronous **hold** before the `await` that's released if payment fails.

**Constraints:** no locks, no `nonisolated(unsafe)`. The fix must keep the actor reentrant (no "actor-wide mutex" via a serial queue).

**Tests**
- `naiveCacheFetchesOncePerConcurrentCaller`: use an `AsyncBarrier(count: 5)` inside the fetch so all 5 are provably concurrent.
- `dedupedCacheFetchesOnce`, `aFailedFetchIsNotCached`
- `naiveDeskDoubleBooks` (barrier of 2), `holdBeforeAwaitPreventsDoubleBooking` (`@Test(arguments: 0..<20)`), `aDeclinedPaymentReleasesTheHold`

**Interview drill**
- Why are Swift actors reentrant? What would non-reentrant actors cause?
- State the rule you'd put in a code-review checklist for reentrancy.
- Why does the in-flight entry need a `defer { inFlight[id] = nil }`?

<details><summary>Hints</summary>

- The bug pattern is always: read state → `await` → write state based on the stale read.
- Fixes: (1) make the critical section synchronous, (2) record intent before the `await`, (3) re-check after the `await`.
</details>

**Read first:** [SE-0306 § Actor reentrancy](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md#actor-reentrancy), WWDC21 [Protect mutable state with Swift actors](https://developer.apple.com/videos/play/wwdc2021/10133/).

---

## C04. `nonisolated` members and `isolated` parameters (L2)

**Concept:** `nonisolated` moves one member *out* of the actor; an `isolated` parameter moves a whole function *in*.

**Task.**
1. `actor HostInbox: Hashable, CustomStringConvertible` keyed by an immutable `hostID`. Satisfy the protocols with `nonisolated` members.
2. Write a free function `triage(_ inbox: isolated HostInbox, keepingLast:)` that calls 2 actor methods synchronously.
3. Add `transaction(_ body: @Sendable (isolated HostInbox) throws -> T) rethrows -> T`.

**Tests:** `nonisolatedMembersAreSynchronous` (no `await` on `hostID` from the test module), `isolatedParameterRunsSeveralOperationsInOneHop`, `transactionsDoNotInterleave` (100 concurrent transactions; each sees a delta of exactly 1).

**Interview drill**
- Why must `Hashable`'s `hash(into:)` be `nonisolated` on an actor?
- What's the difference between N `await inbox.x()` calls and one call to a function with `isolated inbox`?
- Can a `nonisolated` actor method read a `var`? A `let`?

<details><summary>Hints</summary>

⚙️ Predict this: is an actor's `let hostID: Int` readable without `await` **from another module**?
</details>

**Read first:** [SE-0313 Improved control over actor isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0313-actor-isolation-control.md).

---

# Tier 2: Data-race safety

## C05. The `Sendable` ladder and `Mutex` (L2)

**Concept:** `Sendable` means "safe to share across isolation domains". There's a ladder from free (value types) to last resort (`@unchecked`).

**Task.** One type per rung:
1. `struct Quote: Sendable`
2. `final class ExchangeRates: Sendable` (only `let`s)
3. `final class RateLimiter: Sendable` using `Mutex` from `Synchronization`
4. `final class LegacyMetrics: @unchecked Sendable` with an `NSLock` and the justification comment the playbook requires
5. `makeQuoteFormatter(currency:rates:) -> @Sendable (Quote) -> String`

**Tests:** 200 concurrent `tryAcquire` on capacity 10 → exactly 10 granted; 1,000 concurrent `record` → 1,000; formatter used in `Task.detached`.

**Compile-failure snippets to reproduce:** `var` in a `Sendable` class, non-`final` `Sendable` class, `@Sendable` closure mutating a captured `var`, a global `var`.

**Interview drill**
- Why must a `Sendable` class be `final`?
- `Mutex` vs an actor: when do you pick each?
- Why is `@unchecked Sendable` a "last resort", and what would you require in code review to accept it?

**Read first:** [SE-0302 Sendable](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md), [SE-0433 Mutex](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0433-mutex.md).

---

## C06. Region-based isolation and `sending` (L3)

**Concept:** a non-`Sendable` value *can* cross a boundary if the compiler proves nothing else can reach it ("disconnected region"). `sending` puts that requirement in a signature.

**Task.** With a non-`Sendable` `final class ReservationDraft`:
1. Send a freshly created draft to `actor ReservationOutbox` without `sending` anywhere.
2. `makeDraft(…) -> sending ReservationDraft`.
3. `forward(_ draft: sending ReservationDraft, to:) async`.
4. `ReservationOutbox.exportFirst() -> sending ReservationDraft?`: hand out a copy.
5. `annotateInBackground(_ draft: sending ReservationDraft, note:) -> Task<Int, Never>`.

**Compile-failure snippets:** use after send; a parameter (not `sending`) captured by `Task {}`; a copying initializer whose result stays connected; re-sending a value captured by a `Task` closure.

**Tests:** one per function above, plus "mutating the exported copy doesn't change the actor's state".

**Interview drill**
- What is a region? When does the compiler merge two regions?
- What's the difference between `Sendable` and `sending`?
- Why does `Task.init` take a `sending` closure instead of a `@Sendable` one?

<details><summary>Hints</summary>

- ⚙️ Predict: does `return ReservationDraft(copying: first)` satisfy `-> sending`? What does the compiler assume about an initializer that takes a non-Sendable argument?
- ⚙️ Predict: can a `Task` closure pass a captured `sending` value to an actor?
</details>

**Read first:** [SE-0414 Region-based isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0414-region-based-isolation.md), [SE-0430 `sending`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md).

---

## C07. Isolated conformances (L3)

**Concept:** `extension T: @MainActor P` (Swift 6.2) says the conformance only exists on the main actor.

**Task.**
1. `@MainActor final class ListingCardModel` conforming to a nonisolated `protocol PriceDisplaying` and to `Equatable`, both as isolated conformances.
2. A `@MainActor` generic `renderPrices<Card: PriceDisplaying>` and a nonisolated synchronous `firstPrice<Card: PriceDisplaying>`.
3. Reproduce the error when the conformance is used off the main actor (`Task.detached`).

**Tests:** a `@MainActor` suite using both generic functions and `==`.

**Interview drill**
- Before 6.2, what were the three ways to make a `@MainActor` type conform to a nonisolated protocol? What did each cost?
- Why can a nonisolated *synchronous* generic function use a `@MainActor` conformance?
- What does `InferIsolatedConformances` do in an app target?

**Read first:** [SE-0470 Global-actor isolated conformances](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0470-isolated-conformances.md).

---

## C08. Isolation-inheriting helpers and `@isolated(any)` (L3)

**Concept:** generic async helpers (`withRetry`, `measure`, `withTimeout`) should run on the *caller's* actor so they accept non-Sendable closures.

**Task.**
1. `withRetry(attempts:isolation:_:)` using `isolated (any Actor)? = #isolation` (6.0 style).
2. `withRetryNonsending(attempts:_:)` using `nonisolated(nonsending)` (6.2 style).
3. `nonsendingLabel()` and `plainNonisolatedLabel()`: prove where each runs when called from `@MainActor`.
4. `JobQueue` storing `@isolated(any) @Sendable () async -> Void` jobs, reading `job.isolation` synchronously.

**Tests:** call both retries from `@MainActor` with a closure that mutates a **non-Sendable** class; `retryGivesUp`; labels; `isolatedAnyClosuresCarryTheirIsolation`.

**Interview drill**
- Why doesn't `func helper(_ op: () async -> T) async -> T` accept a closure that captures main-actor state (under Swift 6 defaults)?
- `isolated` parameter vs `nonisolated(nonsending)`: same semantics? Which one goes in a public library API today?
- What problem does `@isolated(any)` solve for `Task.init`?

**Read first:** [SE-0420](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md), [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md), [SE-0431 `@isolated(any)`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0431-isolated-any-functions.md).

---

# Tier 3: Approachable concurrency (Swift 6.2+), target `ConcurrencyApp`

## C09. Default `MainActor` isolation (L2)

**Concept:** `.defaultIsolation(MainActor.self)` makes every unannotated declaration `@MainActor`. You opt *out* with `nonisolated`.

**Task.**
1. `SearchModel` (class) and `ListingRow` (struct, `Identifiable`, `Equatable`) with **no** annotations.
2. `nonisolated struct ListingDTO: Decodable, Sendable` and `nonisolated enum PriceMath`.
3. Reproduce: a nonisolated function mutating `SearchModel`; a `Decodable` DTO that *forgot* `nonisolated`, decoded in a `@concurrent` function.

**Tests:** a `@MainActor` test for the model; a **nonisolated** test that decodes `ListingDTO` and calls `PriceMath`.

**Interview drill**
- Which targets should use default `MainActor` isolation? Which shouldn't?
- Why does a forgotten `nonisolated` on a DTO break decoding off the main actor?
- What else does Xcode's "Approachable Concurrency" build setting turn on?

**Read first:** [SE-0466 Control default actor isolation inference](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md), Swift.org [Approachable Concurrency vision](https://github.com/swiftlang/swift-evolution/blob/main/visions/approachable-concurrency.md).

---

## C10. `nonisolated(nonsending)` vs `@concurrent` (L3)

**Concept:** with `NonisolatedNonsendingByDefault`, `nonisolated async` functions run on the caller's actor; `@concurrent` is how you explicitly leave.

**Task.** `ExecutionProbe` with `inheritsCaller()`, `explicitlyNonsending()`, `alwaysOffActor()` (`@concurrent`), and two thread-level checks (`pthread_main_np()`).

**Tests:** from `@MainActor`: the first two report "main", the `@concurrent` one doesn't; from a nonisolated test there's nothing to inherit.

**Interview drill**
- What did `nonisolated async` mean in Swift 5.7–6.1 (SE-0338), and why was that confusing?
- After turning on `NonisolatedNonsendingByDefault` in an existing module, what kind of regression can appear, and how do you find it?
- Can you put `@concurrent` on a synchronous function?

**Read first:** [SE-0461 Run nonisolated async functions on the caller's actor by default](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md), [SE-0338](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md).

---

## C11. Offloading work with `@concurrent` (L2)

**Concept:** in a main-actor-by-default module, heavy work must be explicitly `@concurrent`, touching only nonisolated, `Sendable` types.

**Task.** `ListingDecoder.decode(_:) async throws -> [ListingDTO]` as `@concurrent`; a `SearchLoader` (main actor by default) that awaits it and updates `SearchModel`. No `DispatchQueue`, no `Task.detached`.

**Tests:** decode 10,000 listings from a `@MainActor` test and prove it ran off the main thread; the loader updates the model.

**Interview drill**
- `@concurrent` vs `Task.detached` vs `DispatchQueue.global().async`: what does each inherit (priority, task-locals, cancellation)?
- Which of them is structured?

**Read first:** WWDC25 [Embracing Swift concurrency](https://developer.apple.com/videos/play/wwdc2025/268/).

---

## C12. `isolated deinit` and `Task.immediate` (L3)

**Concept:** two lifecycle tools from Swift 6.2.

**Task.**
1. `PhotoUploadSession` registers itself in a main-actor `UploadRegistry` in `init` and unregisters in an `isolated deinit`. Reproduce the error with a plain `deinit`.
2. `EventLog.startImmediate()` (`Task.immediate`) vs `startEnqueued()` (`Task {}`).

**Tests:** `isolatedDeinitRunsOnTheMainActor` (last release on main → runs inline); `isolatedDeinitIsEnqueuedWhenReleasedElsewhere`; `immediateTasksStartSynchronously` (the first event is logged before the creating code suspends); `regularTasksAreOnlyEnqueued`.

**Interview drill**
- Why is a regular `deinit` always nonisolated, even on a `@MainActor` class?
- When does an `isolated deinit` run inline, and when is it enqueued? What does that mean for ordering?
- Give a UI case where `Task.immediate` fixes a visible bug.

**Read first:** [SE-0371 Isolated synchronous deinit](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0371-isolated-synchronous-deinit.md), [SE-0472 Starting tasks synchronously](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0472-task-start-synchronously-on-caller-context.md).

---

# Tier 4: Structured concurrency

## C13. `async let` vs task groups (L3)

**Concept:** both create child tasks; they differ in *how results are collected*.

**Task.** `QuoteAggregator` over 3 services (nightly, fees, tax):
1. `quote(listingID:)` with `async let`.
2. `quoteFailFast(listingID:)` with a throwing task group.
3. `firstResponse(from:)`: a hedged request across mirrors; keep the first success, cancel the rest.

**Tests:** `asyncLetAwaitsInTheOrderWritten` (fees fails immediately, but the error only surfaces after nightly finishes); `taskGroupFailsFastAndCancelsSiblings`; hedged success and all-fail.

**Interview drill**
- What happens to an `async let` you never `await`?
- Why does a task group not return until cancelled children finish?
- Implement "first of N wins" from memory.

**Read first:** [SE-0317 async let](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0317-async-let.md), [SE-0304 Structured concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md).

---

## C14. Cancellation (L3)

**Concept:** cancellation is a flag plus handlers; nothing stops unless code checks.

**Task.**
1. `ListingImporter.importPages(_:store:)` returns a partial `ImportReport` on cancellation.
2. Bridge `LegacyDownload` (callback + its own `cancel()`) with `withCheckedThrowingContinuation` inside `withTaskCancellationHandler`. Handle **cancel-before-start**.
3. `Inheritance.observeAfterCancelling()`: what do `async let`, `Task {}` and `Task.detached` children see?

**Tests:** partial import; legacy cancel; `cancellationBeforeStartIsNotLost`; completion; inheritance table.

**Interview drill**
- `Task.isCancelled` vs `try Task.checkCancellation()`: when do you use each?
- When does `onCancel` run, and on which thread?
- Why does `Task {}` not inherit cancellation, and why is that both a feature and a trap?

**Read first:** [SE-0304 § Cancellation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md#cancellation).

---

## C15. `AsyncStream` (L2)

**Concept:** the standard bridge from push-based APIs (delegates, callbacks, notifications) into `for await`.

**Task.** `CalendarSyncClient` (observer tokens, `Mutex`) → `changes(bufferingPolicy:) -> AsyncStream<AvailabilityChange>` using `AsyncStream.makeStream` and `onTermination`. A throwing `replay(_:thenFail:)` with `AsyncThrowingStream`.

**Tests:** callback bridging; `onTerminationUnregistersTheObserver` (cancel the consumer); `bufferingNewestKeepsOnlyTheLatest`; throwing streams end with the error.

**Interview drill**
- Which buffering policy for: a progress bar, an event log, a "latest location" feed?
- What happens if two tasks iterate the same `AsyncStream`?
- What leaks if you forget `onTermination`?

**Read first:** [SE-0314 AsyncStream](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md), [SE-0388 makeStream](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0388-async-stream-factory.md).

---

## C16. A custom `AsyncSequence` operator and `Observations` (L3)

**Task.**
1. `RemoveDuplicatesSequence<Base>` that forwards `Base.Failure` (implement `next(isolation:)`), so a non-throwing base needs no `try`.
2. `@MainActor @Observable SearchFilters` with `maxPriceChanges: Observations<Int, Never>`.

**Tests:** `[1,1,2,2,2,3,1]` → `[1,2,3,1]` with `for await` (no `try`); `Observations` emits the initial value, and 3 synchronous mutations produce **one** value.

**Interview drill**
- Why did SE-0421 add `Failure` and `next(isolation:)` to `AsyncIteratorProtocol`?
- `Observations` vs `withObservationTracking` vs Combine's `@Published`?

**Read first:** [SE-0421](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0421-generalize-async-sequence.md), [SE-0475 Transactional observation of values](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md).

---

# Tier 5: Determinism, task context and Swift 6.4

## C17. Injected clocks (L4)

**Concept:** inject `some Clock<Duration>`; test with a `ManualClock` you advance by hand. Tests never sleep.

**Task.**
1. `ManualClock: Clock` with `advance(by:)`, a cancellable `sleep(until:)`, and `waitForSleepers(_:)` so tests never race the code under test.
2. `retrying(_:clock:operation:)` with exponential `Backoff`.
3. `withTimeout(_:clock:operation:)`.

**Tests:** delays 100/200/400 ms; retries only when time moves; gives up; cancelling during backoff; timeout fires; fast operations beat the timeout.

**Interview drill**
- Why is `Task.sleep` in a test a smell? What's the deterministic alternative?
- What must `ManualClock.sleep` do if the task is cancelled *before* it registers?

<details><summary>Hints</summary>

`withTaskCancellationHandler`'s `onCancel` can run before the operation body. Remember cancelled IDs.
</details>

---

## C18. Task-locals and priority escalation (L3)

**Task.**
1. `@TaskLocal static var requestID`; `logLine(_:)`; `observeTaskLocalPropagation()` across `async let`, a group child, `Task {}` and `Task.detached`.
2. `Prefetch`: a `.low` task using `withTaskPriorityEscalationHandler`; escalate it with `task.escalatePriority(to: .high)`.

**Tests:** the propagation table; scoping; `priorityEscalationIsObservable`.

**Interview drill**
- What are task-locals good for? What are they bad for?
- How does Swift avoid priority inversion when a high-priority task awaits a low-priority one?

**Read first:** [SE-0311 Task-local values](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0311-task-locals.md), [SE-0462 Task priority escalation APIs](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0462-task-priority-escalation-apis.md).

---

## C19. Async cleanup: `await` in `defer` and cancellation shields (Swift 6.4) (L4)

**Concept:** cleanup must run on every exit path **and** be able to finish when the task was cancelled.

**Task.**
1. `shielded(_:)`: the portable shield (an unstructured task).
2. `withAsyncCleanup(_:cleanup:)` (works on 6.0+).
3. Swift 6.4: `syncReleasingInDefer` using `defer { await lease.release() }`, and `syncReleasingInShieldedDefer`.
4. `withTaskCancellationShield` behind `#if HAS_TASK_CANCELLATION_SHIELD`.

**Tests:** cleanup after success/failure; `cleanupIsShieldedFromCancellation`; `awaitInDeferRunsCleanupButInsideTheCancelledTask`; `shieldedDeferLetsCleanupFinish`; `unshieldedCleanupSeesCancellation`.

**Interview drill**
- Why isn't `defer { await … }` enough on its own for "release the lease on the server"?
- Why was `withTaskCancellationShield` added instead of telling people to use `Task {}`?

<details><summary>Hints</summary>

⚙️ Try calling `withTaskCancellationShield` inside `if #available(macOS 27, *)` and *run* the binary on macOS 26.
</details>

**Read first:** [SE-0493 async calls in defer](https://forums.swift.org/t/accepted-se-0493-support-async-calls-in-defer-bodies/83023), [SE-0504 Task cancellation shields](https://forums.swift.org/t/accepted-se-0504-task-cancellation-shields/84667).

---

## C20. Bounded and discarding task groups (L3)

**Task.**
1. `PhotoUploader.uploadAll(_:maxConcurrent:upload:)`: at most N in flight, results in input order.
2. `WebhookProcessor.process(_:handle:)` with `withThrowingDiscardingTaskGroup`.

**Tests:** `@Test(arguments: [1, 3, 8])` peak ≤ limit and order kept; a failure fails the batch; 100 events handled; the first error is rethrown.

**Interview drill**
- Why is "one `addTask` per item" a production incident for 100,000 items?
- When is a discarding group the right tool?

**Read first:** [SE-0381 Discarding task groups](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0381-task-group-discard-results.md).

---

# Capstone: migrate BookingSync by hand

The plan's milestone: *"a second, harder module (actors, async streams, a reentrancy bug) migrated by hand with zero warnings, and the playbook upgraded to v2 with approachable-concurrency and `@concurrent` rules."*

It lives in the `swiftmigrator` repo: `fixtures/before/BookingSync` → `fixtures/after/BookingSync`, with [`MIGRATION_TASKS.md`](../../swiftmigrator/fixtures/before/BookingSync/MIGRATION_TASKS.md) listing every planted issue.

**Definition of done**
- [ ] `swift build` of the `after` package: 0 errors, 0 warnings, Swift 6 mode, warnings as errors.
- [ ] `swift test` green 10 times in a row.
- [ ] Every planted issue fixed by a playbook rule (v1 R1–R16 or new v2 R17–R25), cited in the report.
- [ ] Regression tests for the bugs the compiler can't see (reentrancy, the leaked polling task, cooperative-pool starvation).
- [ ] `MIGRATION_PLAYBOOK.md` v2 written from what you learned.
