# Combine ↔ Swift Concurrency: one search, two implementations

Day 5, second milestone: *"the Combine search pipeline and its `AsyncSequence` rewrite pass the same tests, and the playbook gains a Combine → async/await and `@Published` → `@Observable` section."*

- Code: `Sources/Combine/` (target `CombineSearch`; the directory is named `Combine`, the target is not, so it never shadows Apple's `Combine` module)
- Tests: `Tests/CombineSearchTests/`
- Playbook: `swiftmigrator/playbook/MIGRATION_PLAYBOOK.md` R26–R29, fixture `swiftmigrator/fixtures/{before,after}/SearchKit`

## The behavior (acceptance criteria)

A listings search box. Raw text goes in, `SearchOutput` (`.results` or `.failed`) comes out. Debounce is 300 ms.

| AC | Behavior |
|---|---|
| AC-1 | Rapid typing is coalesced into one search, for the last text |
| AC-2 | Every keystroke restarts the debounce timer |
| AC-3 | A query equal to the previous one (after trimming) does not search again |
| AC-4 | A blank query clears the results without calling the service |
| AC-5 | A slow response for a superseded query is never emitted |
| AC-6 | A superseded search is *cancelled*, not just ignored |
| AC-7 | A failing search is reported, and the pipeline keeps working |
| AC-8 | Tearing the pipeline down cancels the search in flight |

`SearchContractTests` runs **the same eight test bodies** against `CombineSearchPipeline` and `AsyncSearchPipeline` through one `SearchHarness` protocol. 16 cases, no `sleep`.

## Files

| File | What it is |
|---|---|
| `SearchModels.swift` | `Hit`, `SearchOutput`, `SearchService`, `SearchConfig` |
| `CombineSearchPipeline.swift` | `map → debounce → removeDuplicates → map(publisher) → switchToLatest`, `@MainActor`, generic over `Scheduler` |
| `AsyncOperators.swift` | hand-written `debounced`, `removingDuplicates`, `mapLatest` returning `AsyncStream` |
| `AsyncSearchPipeline.swift` | the same chain on `AsyncSequence`, generic over `Clock` |
| `Bridges.swift` | `stream(of:)` (Combine → `AsyncStream`), `taskPublisher` (async → Combine, cancels its `Task`) |

Test support: `ManualScheduler` (a Combine `Scheduler` whose time only moves on `advance`), `ManualClock` (from C17), `CountingClock`, `FakeSearchService` (answers, fails, or *holds* a call), `OutputRecorder`.

## What the exercise taught (read before the interview)

1. **Combine needs a fake scheduler; async needs a fake clock.** `debounce(scheduler:)` with `DispatchQueue.main` means a real 300 ms wait in every test. Both versions are injectable, and the contract can't tell which one it's driving.
2. **`switchToLatest` cancels, but only if you wire it.** `Future { Task { … } }` does not cancel the `Task` when the subscriber cancels: `taskPublisher` adds `handleEvents(receiveCancel:)`. AC-6 fails (it hangs waiting for the cancellation) without it, while AC-5 still passes, because the stale value is ignored but the work keeps running.
3. **A cancelled task can still return a value.** `mapLatest` yields only if its generation is still current, checked and yielded in one critical section. Checking `Task.isCancelled` and then yielding leaves a window for a stale result.
4. **`share()` keeps the chain alive while any one subscriber remains.** The first version of the Combine pipeline used it and AC-8 hung: "the view went away" no longer cancelled the search. The cold publisher lets the subscriber's `AnyCancellable` own the lifetime.
5. **`publisher.values` subscribes at the first `next()`.** `stream(of:)` subscribes at the call, so nothing sent before the loop is lost.
6. **`break` does not end an `AsyncStream` you still reference.** Termination needs a cancelled consumer or the last reference to go away. The first version of a bridge test hung (and starved other main-actor tests with a `Task.yield()` loop) because of this.
7. **Combine isn't `Sendable`, and you don't need `@unchecked`.** Keeping the pipeline and its bridge `@MainActor` is enough. The only place a `Sendable` closure needs a Combine value (`onTermination`) uses a `@MainActor` box. No `@preconcurrency`, no `@unchecked` anywhere in `Sources/Combine`.
8. **A debounce test must wait for the timer to exist.** After `type("pa")` the async version registers its timer from another task. Waiting for "someone is sleeping" can be satisfied by the previous, about-to-be-cancelled timer, so `CountingClock` counts sleeps *started*.
9. **Typing again supersedes the search in flight** in the Combine harness, because `type` doesn't suspend. The first AC-7 test hung for that reason: the harness must wait for an output before typing again when the test needs that search to finish.

## Interview drill

- Why can't you test `debounce(for:scheduler: DispatchQueue.main)` deterministically, and what do you inject instead?
- What does `switchToLatest` do to the previous inner publisher, and what must your async bridge do for that to reach the network call?
- You replaced `.sink` with a `Task`. What are the two ways a stale response can still overwrite a newer one?
- `publisher.values` vs an `AsyncStream` that subscribes eagerly: when does it matter?
- When would you keep Combine in 2026? (an existing multi-stage pipeline with `combineLatest`/`merge` operators and no appetite for `swift-async-algorithms`; framework APIs that still publish; a team that has the tests.)
