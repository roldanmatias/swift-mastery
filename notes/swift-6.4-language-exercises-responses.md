# Swift 6.4 Language Core: Responses

Solutions, short theory and interview-drill answers for [swift-6.4-language-exercises.md](swift-6.4-language-exercises.md). Every solution is real code in this repo, and every claim below was checked against a compiler.

## How this was verified

| What | Result |
| --- | --- |
| Toolchain | **Swift 6.4.2** (swiftly, pinned in `.swift-version`) and **Swift 6.3.2** (Xcode 26.5) on macOS 26, Intel |
| `swift test` on 6.4.2 | **160 tests pass**: Language 101, macros 10, Ownership 31, StayKit 18. 1 documented known issue (a compiler bug, Ex 05). 6 tests skipped automatically because they need macOS 27 |
| `xcrun swift test` on 6.3.2 | **147 tests pass**. The 6.4-only code is compiled out with `#if compiler(>=6.4)` |
| `swift build -c release` on 6.4.2 | Builds after working around an optimizer crash (Ex 30) |
| Access control | Nothing is `public`. Declarations other modules use are `package` (visible to every target in this package, nobody else); everything else is `internal`, and tests use `@testable import`. Hand-written inits that only existed because of `public` were removed in favor of memberwise inits |
| Compile errors quoted in this doc | **25/25** reproduced by [`scripts/verify-compile-errors.sh`](../scripts/verify-compile-errors.sh) (full compile, so SIL-level diagnostics are included) |

Read the **Read first** resource for each exercise before its answer. Then try to answer the drill out loud *before* reading the answer.

## Findings from running real Swift 6.4.2 (read this first)

Several things behave differently from what the proposals and articles suggest. These are worth knowing in an interview because they show you've actually used the features.

| # | Finding | Where |
| --- | --- | --- |
| 1 | **Compiler bug:** a module selector on an extension *member* (`name.Pricing::slug`) compiles but calls the wrong module's extension, on 6.3.2 and 6.4.2. Top-level names (`Pricing::Money`) and nested types (`Ship.A::Engine`) work. Repro: [`scripts/compiler-bugs/member-module-selector.sh`](../scripts/compiler-bugs/member-module-selector.sh) | Ex 05 |
| 2 | **Compiler crash:** any recursive noncopyable type linked through `UniqueBox` (`var next: UniqueBox<Node>?`) crashes the 6.4.2 optimizer at `-O` (assertion in `SILBitfield`, pass `SwiftArrayPropertyOpt`) on x86_64 and arm64. Repro: [`scripts/compiler-bugs/recursive-uniquebox-optimizer-crash.swift`](../scripts/compiler-bugs/recursive-uniquebox-optimizer-crash.swift) | Ex 30 |
| 3 | `UniqueArray` and `UniqueBox` ship in the **standard library** (there's no `Containers` module) but are **availability-gated to macOS 27**. **`RigidArray` isn't in 6.4.2** | Ex 30 |
| 4 | SE-0499 is only partly shipped: `Equatable`, `Comparable` and `Hashable` work for noncopyable types (and are **synthesized**). `CustomStringConvertible` (so interpolation) and `Optional == Optional` don't | Ex 28 |
| 5 | `discard self` still requires **trivially-destroyed** stored properties. It's a SIL-level error, so `swiftc -typecheck` won't show it, only a real build | Ex 24 |
| 6 | A `mutate` accessor can return `&storedProperty` or `&box.value`, but not `&uniqueArray[i]`. `yielding mutate` is still experimental | Ex 30 |
| 7 | `deinit` can't mutate `self` yet (SE-0544 is accepted, not implemented). Iterative destruction needs a small class that owns the chain | Ex 30 |
| 8 | Swift Testing's `#expect` **can't take noncopyable operands or receivers**. Closures can only *borrow* captured noncopyable values, so `#expect(throws:) { try consume(x) }` doesn't compile | Tests |
| 9 | A generic typed-throws `@autoclosure` (`() throws(E) -> T`) can't infer `E == Never`. Use `rethrows` (that's why the stdlib's `??` does) | Ex 03 |
| 10 | `for x in inlineArray` on 6.4 says the type must conform to **`Iterable`, available on macOS 27**: `InlineArray` becomes iterable there (SE-0516) | Ex 29 |
| 11 | Module selectors in practice: `Host` is ambiguous with Foundation's macOS `Host` class (`Language::Host`), and `PaymentToken` exists in two of our modules (`StayKit::PaymentToken`) | Ex 05, tests |
| 12 | A `static let` key path from `appending(path:)` isn't `Sendable`. Only literals typed `KeyPath<…> & Sendable` can be stored globally | Ex 09 |
| 13 | `Array(lazyFilter.prefix(n))` on a lazy filter **collection** re-runs the predicate (6 calls to return 1 element). One `for` loop runs it once per element | Capstone |
| 14 | `.lazy` can't be called on `any Collection<T>`; open the existential through a generic function | Capstone |
| 15 | On 6.3, the memberwise init of a struct with a `private var x = …` is `private`. On 6.4 (SE-0502) that property is excluded and the init stays `internal` | Capstone |

### Code map

| Exercise | Solution | Tests |
| --- | --- | --- |
| 01–23 | [`Sources/Language/E01…E23_*.swift`](../Sources/Language) | [`Tests/LanguageTests/`](../Tests/LanguageTests) |
| 05 modules | [`Sources/Payments`](../Sources/Payments), [`Pricing`](../Sources/Pricing), [`Listing`](../Sources/Listing) | Tier1Tests |
| 20 | [`Sources/Migration/LegacyListingAdapter.swift`](../Sources/Migration/LegacyListingAdapter.swift) | Tier4And5Tests |
| 23 | [`Sources/LanguageMacros/`](../Sources/LanguageMacros), [`Sources/LanguageMacrosClient/`](../Sources/LanguageMacrosClient) | [`Tests/LanguageMacrosTests/`](../Tests/LanguageMacrosTests) |
| 24–30 | [`Sources/Ownership/E24…E30_*.swift`](../Sources/Ownership) | [`Tests/OwnershipTests/`](../Tests/OwnershipTests) |
| Benchmarks | [`Benchmarks/OwnershipBenchmarks/main.swift`](../Benchmarks/OwnershipBenchmarks/main.swift) | `swift run -c release OwnershipBenchmarks` |
| Capstone | [`Sources/StayKit/`](../Sources/StayKit) | [`Tests/StayKitTests/`](../Tests/StayKitTests) |

Each exercise below has three parts: **Theory** (the idea in a few lines), **Solution** (the key code and what the tests prove) and **Interview drill** (one answer per question from the exercises file).

---

# Tier 1: Types and semantics

## 01. Value vs reference semantics

**Theory.** A type has *value semantics* when mutating one variable can never be observed through another variable. The `struct` keyword doesn't guarantee it: a struct is only as value-like as its stored properties. A struct that stores a class reference shares that object between copies. Reference semantics (classes) are right when **identity** is the meaning: "this host", "this connection".

**Solution:** [E01_ValueSemantics.swift](../Sources/Language/E01_ValueSemantics.swift)

```swift
// Broken: a struct, but copies share the gallery object
final class PhotoGalleryRef { var urls: [URL] }
struct BrokenListing { var gallery: PhotoGalleryRef }

// Fixed by construction: every stored property is a value type
struct PhotoGallery: Equatable, Sendable { var urls: [URL] }
struct Listing {
    var gallery: PhotoGallery   // `listing.gallery.urls.append(x)` still compiles
    var host: Host              // deliberately shared: a Host is an identity
}
package final class Host { package let id = UUID(); package var name: String }
```

The tests prove that a copy of `BrokenListing` mutates the original, even through a `let`. In the fixed `Listing` a copy is independent, while `host` stays shared (`===`). The compile error for mutating a `let` fixed listing is verified: *"cannot use mutating member on immutable value: 'fixed' is a 'let' constant"*.

**Interview drill**

- **Define value semantics without "struct" or "copy".** Each variable holds its own independent value. Changing what one variable holds can never be seen through any other variable, so only the value matters, never "which one".
- **Where do structs live?** Wherever the compiler decides. The stack is an optimization, not a rule. A struct is on the heap when it's:
  1. captured by an escaping closure (boxed);
  2. a stored property of a class instance;
  3. inside an existential larger than the 3-word inline buffer;
  4. an `indirect` enum payload;
  5. an element of an `Array`/`Dictionary` (the buffer is on the heap);
  6. a local of an `async` function (async frames are heap-allocated).

  The reverse also happens: the optimizer can stack-promote class instances that don't escape.
- **When choose a class in Swift 6?**
  - When identity is the semantics (a `Host`, a connection, a cache).
  - For `@Observable` models (Observation requires classes).
  - For UIKit/AppKit subclassing and Objective-C interop.
  - For shared mutable state, though under Swift 6 that usually means an **actor**, or a `final class` that is `Sendable` because it uses `Mutex` or immutable `let`s.

  "Exactly-once cleanup" used to be a reason too. Now a `~Copyable` struct with a `deinit` (Ex 24) is often better.

---

## 02. Enums with associated values and pattern matching

**Theory.** Pattern matching is a mini-language:
- value patterns (`.nightly(0)`)
- binding patterns (`let x`)
- tuple patterns (`(a, .percentOff(b, inner))`)
- `where` guards
- `case` in `if`, `guard` and `for`
- expression patterns resolved through `~=`

`switch` must be **exhaustive**: adding a case turns every incomplete switch into a compile error. `indirect` stores the payload in a heap box so a recursive enum has a finite size.

**Solution:** [E02_PatternMatching.swift](../Sources/Language/E02_PatternMatching.swift)

```swift
package indirect enum PricingRule: Equatable, Sendable {
    case nightly(Decimal), cleaningFee(Decimal)
    case percentOff(Int, PricingRule), combined(PricingRule, PricingRule)
    case ifStayAtLeast(nights: Int, then: PricingRule, else: PricingRule)
}

// Bottom-up simplifier with nested tuple patterns
private static func simplifyPercent(_ percent: Int, _ rule: Self) -> Self {
    switch (percent, rule) {
    case (0, let rule): return rule
    // Discounts compose multiplicatively: (1-a)(1-b) = 1-(a+b-ab/100). Merge only if it stays an Int.
    case let (a, .percentOff(b, inner)) where (a * b) % 100 == 0:
        return simplifyPercent(a + b - (a * b) / 100, inner)
    default: return .percentOff(percent, rule)
    }
}

// Custom pattern type
static func ~= (pattern: StayLength, value: Int) -> Bool { pattern.nights.contains(value) }
switch nights { case StayLength.weekly: "weekly stay" … }

// for case: filter + destructure
for case .cleaningFee(let fee) in rules { total += fee }
```

The trick question in step 2: 50% off twice is **75%**, not 100%. 10% then 15% is 23.5%, which isn't an `Int`, so it stays nested. The tests check `total` over 8 parameterized trees. They also check that `simplified()` is **idempotent** and **preserves meaning** for 1–40 nights on 13 trees.

**Interview drill**

- **What does `indirect` change in memory?** The payload of that case is stored in a heap-allocated, reference-counted box, and the enum stores a pointer to it. Without `indirect`, `PricingRule` would need to contain itself inline: an infinite size. Copies share the box. It's immutable, so value semantics hold.
- **Why exhaustive switches, and what does `@unknown default` do?** Exhaustiveness makes adding a case a compile-time change: every switch that must handle it breaks. `@unknown default` is for **non-frozen enums from resilient libraries** (the SDK), which may gain cases in a future OS. It still handles unknown future values at runtime, but the compiler *warns* if you forget a case that's known today. (Swift 6.2.3's `@extensible`, SE-0487, brings the same model to non-resilient packages.)
- **How does `~=` work in `switch`?** For an expression pattern, `case P:` compiles to `P ~= subject`. The stdlib defines `~=` for `Equatable` values and for ranges. You add your own overload `static func ~= (pattern: MyType, value: Subject) -> Bool`.

---

## 03. Optionals from first principles

**Theory.** `Optional<Wrapped>` is an ordinary enum (`.none`, `.some(Wrapped)`), plus compiler sugar:
- `T?` and `nil` (through `ExpressibleByNilLiteral`)
- `if let` / `guard let`
- `?.` chaining
- `!`
- `??` (an `@autoclosure` function)

**Solution:** [E03_Optionals.swift](../Sources/Language/E03_Optionals.swift)

```swift
enum Maybe<Wrapped> {
    case none, some(Wrapped)
    func map<U, E: Error>(_ f: (Wrapped) throws(E) -> U) throws(E) -> Maybe<U> { … }
}
extension Maybe: ExpressibleByNilLiteral { init(nilLiteral: ()) { self = .none } }
extension Maybe: Equatable where Wrapped: Equatable {}

infix operator |?: NilCoalescingPrecedence
func |? <T>(lhs: Maybe<T>, rhs: @autoclosure () throws -> T) rethrows -> T

// The double optional of a [String: Int?] lookup
switch overrides[key] {          // Int??
case .none: .missing             // key not in the dictionary
case .some(.none): .explicitNil  // key present, value nil
case .some(.some(let v)): .value(v)
}
```

**Finding:** I first wrote `|?` with typed throws (`rhs: @autoclosure () throws(E) -> T`). Calling it with a non-throwing expression fails: *"generic parameter 'E' could not be inferred"*. `rethrows` works, and the stdlib's `??` uses it. The tests prove the right side is **not evaluated** when the left is `.some` (counter stays 0), and that `.some(.none)` is told apart from `.none`.

**Interview drill**

- **What does `a?.b?.c()` desugar to?** Roughly:

  ```swift
  switch a {
  case .none: nil
  case .some(let a):
      switch a.b {
      case .none: nil
      case .some(let b): .some(b.c())
      }
  }
  ```

  The whole chain short-circuits at the first `nil`, and the result is *one* level of optional: if `c()` already returns `T?`, the result is still `T?`, not `T??`.
- **`if let x`, `guard let x`, `if let x = x`?** `if let x = x` binds a non-optional `x` in the `if` body. SE-0345 (Swift 5.7) lets you write just `if let x` when shadowing a variable of the same name. `guard let` binds the value in the *enclosing* scope, and its `else` must exit (return, throw, break or continue).
- **Why is `@autoclosure` dangerous in APIs?** The call site looks like a plain value, but it's a closure. The reader can't see that the expression may run **zero times, later, or many times**. Side effects (`log(); counter += 1`) silently may not run, expensive work can run at a surprising time, and an `@escaping` autoclosure can capture state and outlive the call. Use it only where laziness is the obvious contract (`??`, `assert`, `&&`).

---

## 04. Extensions and method dispatch

**Theory.** Swift has three kinds of dispatch:

1. **Static** (direct call): struct methods, `final`/`private` members, and *non-requirement* protocol-extension methods.
2. **Witness table** (protocol requirements called through a generic `T: P` or `any P`).
3. **vtable** (overridable class methods).

A method in a protocol extension that is *not* a requirement has no witness-table slot, so the call site's *static type* decides which one runs.

**Solution:** [E04_Dispatch.swift](../Sources/Language/E04_Dispatch.swift). The test table has 14 call sites, all predicted before running:

| Call site | Result | Why |
| --- | --- | --- |
| `Listing().summary()` / `.badge()` | listing / listing | static type is `Listing` |
| `<T: Describable>` → `summary()` | listing summary | requirement → witness table |
| `<T: Describable>` → `badge()` | **generic badge** | not a requirement → static, picks the extension |
| `any Describable` → `summary()` / `badge()` | listing / **generic** | same rules as generics |
| `PremiumCard().summary()` | premium summary | static type `PremiumCard` |
| `(PremiumCard() as BaseCard).summary()` | **generic summary** | `BaseCard` has no `summary` member of its own |
| `PremiumCard` via generic / `any` | **generic summary** | `BaseCard`'s witness table was built at conformance and points to the default |
| Fix 1 (`open func summary()` in base + `override`) | premium summary | requirement → witness → vtable |
| Fix 2 (composition, conforms directly) | premium summary | no inheritance trap |

`PremiumCard.summary()` compiles **without** `override`, because there's nothing in the vtable to override. That's the bug: it *shadows*, it doesn't *override*.

**Interview drill**

- **Protocol witness table vs vtable; which does `any Describable` use?** A witness table is one table per *(type, protocol)* conformance, holding function pointers for every requirement. Generic functions receive it as a hidden parameter, and an existential container stores a pointer to it. A vtable is one table per *class*, with one slot per overridable method; subclasses replace slots. `any Describable` uses the **witness table**. If the conforming type is a class, the witness may then forward to the vtable (that's what Fix 1 relies on).
- **Why can't you override a method declared in a class extension (without `@objc dynamic`)?** A class's vtable layout is fixed by its main declaration, and extensions can live in other modules, possibly compiled later. Extension members get no vtable slot, so they're statically dispatched. `@objc dynamic` switches to Objective-C message dispatch, which can be overridden at runtime.
- **How does whole-module optimization change dispatch?** With the whole module visible, the compiler can prove that an `internal` class has no subclasses (so it's treated as `final`), devirtualize the calls and inline them, and specialize generics for concrete types. `private`/`fileprivate` members are implicitly final for the same reason. Across modules, CMO (cross-module optimization, on by default in SwiftPM release builds) and `@inlinable` extend this.

---

## 05. Module selectors `Module::Name` (SE-0491, Swift 6.3)

**Theory.** `Module::name` tells name lookup which module a declaration must come from.
- On an **unqualified** lookup it starts at the module's top level, skipping local and nested scopes.
- On a **qualified** member lookup (`x.Module::member`) it should pick that module's extension member.
- You can't use it on new declarations.

**Solution:** [E05_ModuleSelectors.swift](../Sources/Language/E05_ModuleSelectors.swift) and the three colliding modules.

```swift
static func convert(_ money: Payments::Money) -> Pricing::Money { … }
func topLevelMoney() -> Language::Money { … }   // skips the nested Checkout.Money
static func importedListing(title: String) -> Listing::Listing { … }  // module and type share a name
(name.Payments::slug, name.Pricing::slug)                // member selectors
```

**Verified results**
- `Payments::Money`, `Language::Money` (skipping the nested type) and `Listing::Listing` all work.
- **Compiler bug:** `name.Pricing::slug` compiles but returns `"pay-loft"`. Both member selectors call the *same* extension. A standalone repro shows the same on 6.3.2 and 6.4.2, for properties and methods. Nested types (`Ship.A::Engine`) do resolve correctly. The test uses `withKnownIssue`, so it will start failing when a fixed compiler ships. The `swiftlang/swift` PR that implemented module selectors explicitly lists members (`"…".Foundation::data(using:)`) as supported, so this is a bug, not a design limit.
- `struct Payments::Refund {}`: *"expected '{' in struct"*. New declarations always belong to the current module, so a selector there would be redundant or a lie, and the parser rejects it outright.
- **Real-world cases found while doing the other exercises:** `Tagged<Host, String>` was ambiguous in a test, because Foundation on macOS has a `Host` class, so `Language::Host` fixed it. `PaymentToken` exists in `Ownership` and `StayKit`, so `StayKit::PaymentToken` fixed that.

**Interview drill**

- **Qualified vs unqualified lookup: which does `Module::` affect?** Both. Unqualified lookup (a bare name) normally searches outward through local scopes → types → the current module → imports. `Module::` restricts it to that module and starts at its top level, which is how you reach a top-level type shadowed by a nested one. A qualified lookup (`base.member`) normally sees members from every imported extension. `base.Module::member` restricts it to that module's extensions. (The last part is buggy on 6.3/6.4, see above.)
- **Why is it useful for macro authors and generated code?** Expansions are pasted into the *user's* scope, where the user may have declared their own `Result`, `URL` or `Task`. A macro that emits `Swift::Result` or `Foundation::URL` can't be hijacked by local names. Code generators get the same guarantee.
- **How does it help a migration agent in a monorepo?** Rewrites become context-independent. The agent can emit fully qualified references without first analyzing every local name in the file. Adding an import no longer risks new ambiguity errors, and the module/type-same-name problem (`XCTest.XCTest`, `Listing.Listing`) disappears. But a *member* selector currently resolves to the wrong declaration without any warning, so an agent must still verify the result with tests (the bug I found here).

---

## 06. Copy-on-write by hand

**Theory.** CoW keeps value semantics cheap. A copy just shares the buffer (one retain). Right before a *mutation*, `isKnownUniquelyReferenced` checks whether anyone else holds the buffer, and clones it only if so.

**Solution:** [E06_CopyOnWrite.swift](../Sources/Language/E06_CopyOnWrite.swift)

```swift
package struct AvailabilityCalendar: Equatable, Sendable {
    private final class Storage: @unchecked Sendable { var days: [DayInfo] }
    private var storage: Storage

    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(days: storage.days) }
    }

    package subscript(day: Int) -> DayInfo {
        get { storage.days[day] }
        _modify { makeUnique(); yield &storage.days[day] }   // in place: calendar[3].price += 10
    }
}
```

Why `_modify` and not 6.4's `mutate`: `mutate` must *return* a stored address. Here we have to run `makeUnique()` first and then yield into an array element behind a class reference, which is exactly what a yielding (coroutine) accessor is for. In 6.4.2, `yielding mutate` is still experimental, and `mutate` can't return `&array[i]` (see Ex 30). `_modify` is underscored but it's what the stdlib uses.

**The CoW-defeating bug (step 4).** Holding *one* extra reference costs only *one* copy: after it, the buffer is unique again. The real O(n²) pattern is taking a **snapshot on every mutation** (an undo history):

```swift
for day in 0..<calendar.count {
    history.append(calendar)          // just a retain…
    calendar[day].price = price       // …but now shared → full copy, every iteration
}
```

The test measures **50 copies for 50 days**. The fix is a bulk mutation (one uniqueness check, at most one copy), or storing diffs instead of snapshots.

**Interview drill**

- **Is CoW automatic for every struct?** No. `Array`, `Dictionary`, `Set` and `String` implement it themselves (Foundation's `Data` too). A struct made only of those types gets CoW *for each property*. A struct wrapping a class gets **reference** semantics unless you write CoW yourself, as here.
- **Why `final class`? What about `weak`/`unowned`?** `isKnownUniquelyReferenced` works on native Swift class references. `final` keeps a subclass from adding shared state and lets the uniqueness check and calls be devirtualized. `weak` and `unowned` references don't count as strong references, so a buffer can report "unique" while a weak reference somewhere still sees it change. Never hand out weak or unowned references to CoW storage.
- **Is CoW thread-safe?** As thread-safe as any value type. Each thread owns its own *variable*, and a uniqueness check that returns `true` proves no other variable references the buffer, so mutating it can't race. What isn't safe is two threads mutating the **same variable** (a data race on the variable, CoW or not), which Swift 6's `Sendable` checking rejects. That reasoning is why `Storage` can be `@unchecked Sendable` here.

---

# Tier 2: Functions and closures

## 07. `inout` and the Law of Exclusivity

**Theory.** `inout` means copy-in/copy-out: the callee works on its own copy, and the result is written back when it returns (the optimizer usually passes the address instead). During the call, the caller's variable is under an **exclusive** access. Overlapping accesses are rejected at compile time when the compiler can prove them, and trapped at runtime otherwise (class properties, globals, escaping captures).

**Solution:** [E07_InoutExclusivity.swift](../Sources/Language/E07_InoutExclusivity.swift)

| Situation | Result (verified) |
| --- | --- |
| `didSet` property passed `inout` to a function that mutates it 3 times | **`didSet` fires once** (one write-back) |
| `transfer(&x, &x)` | *"inout arguments are not allowed to alias each other"* |
| `swap(&nights[0], &nights[1])` | *"overlapping accesses to 'nights', but modification requires exclusive access; consider calling MutableCollection.swapAt(_:_:)"* |
| `nights.swapAt(0, 1)` | fine: one access to the array |
| class property mutated inside a closure while passed `inout` | compiles, **traps** at runtime ("Simultaneous accesses"), proven with a Swift Testing **exit test** |
| `balance(&stay.nights, &stay.guests)` on a *local* struct | allowed: the compiler proves the properties are disjoint |

```swift
@Test func exclusivityViolationTraps() async {
    await #expect(processExitsWith: .failure) { E07.triggerExclusivityViolation() }
}
```

**Interview drill**

- **Why enforce exclusivity at all?**
  - **Optimization:** with no aliasing, values can stay in registers, and an `inout` can be passed by address safely.
  - **Memory safety:** you can't mutate an array while a mutating access into it is in progress, so no dangling element pointers.
  - **Predictable semantics:** copy-in/copy-out actually holds.
  - **CoW correctness:** uniqueness checks assume no one else is mutating.

  Swift 5 turned on runtime enforcement in release builds too.
- **`inout` vs `UnsafeMutablePointer` vs a class reference?**
  - `inout`: the default. Scoped, exclusive, checked, no lifetime to manage.
  - `UnsafeMutablePointer`: C interop or manual memory, with no exclusivity checks and no lifetime safety.
  - A class reference: long-lived *shared* mutable state where identity matters. It comes with aliasing and (in Swift 6) Sendable concerns.

---

## 08. Escaping closures and capture lists

**Theory.** A closure captures **variables** (by reference, through a box), not values, unless you list them in a capture list (`[title]`, which copies the value at creation). Escaping closures stored by an object you own create retain cycles when they capture `self` strongly.

**Solution:** [E08_Closures.swift](../Sources/Language/E08_Closures.swift)

```swift
onChange = { print(self.title) }                    // cycle: self → onChange → self
loader.load(url) { data in self.imageData = data }  // cycle: self → loader → completions → self

onChange = { [weak self] in guard let self else { return }; print(self.title) }   // fix A
onChange = { [unowned self] in print(self.title) }  // fix B: safe ONLY because self owns onChange
let closure = { [title] in "Loading \(title)" }     // fix C: capture the value, not self

withoutActuallyEscaping(predicate) { escapable in values.lazy.filter(escapable).count }
```

The tests check deallocation with a `weak` reference after the scope ends. The leaking version is still alive, and all three fixes are deallocated. The capture semantics test gives `byReference == 200` and `snapshot == 100`. For the loader completion, Fix B uses `weak`: the loader can outlive the model, so `unowned` would crash there.

**Interview drill**

- **Why are closure parameters non-escaping by default?** A non-escaping closure can't outlive the call. So the compiler can allocate its context on the stack with no retain/release, implicit `self` is allowed, and retain cycles are impossible. Escaping is the exception, so you mark it.
- **`[weak self]` + `guard let self` vs `self?.` chains?** `guard let self` makes `self` strong for the rest of the closure, so a multi-step operation runs *completely or not at all*. With `self?.a(); self?.b()`, `self` can be deallocated between the two calls, and you get half an operation. Prefer `guard let self` when the steps must be atomic.
- **What does `@Sendable` add?** Every capture must be `Sendable`, and you can't capture a mutable `var` by reference (it would be shared across concurrency domains), only immutable values. In Swift 6 the closure is also checked for isolation (a `@Sendable` closure is non-isolated unless annotated). `sending` (SE-0430) is the more flexible alternative when ownership is transferred instead of shared.

---

## 09. Key paths

**Theory.** A key path is a first-class, type-safe reference to a property. `KeyPath<Root, Value>` is read-only, `WritableKeyPath` writes through an `inout` root, and `ReferenceWritableKeyPath` writes through a class reference. They compose (`appending`), work as functions (`map(\.title)`, SE-0249) and can be stored.

**Solution:** [E09_KeyPaths.swift](../Sources/Language/E09_KeyPaths.swift)

```swift
// Erase the Value type by storing a comparator, not the key path
package struct SortRule<Root> {
    private let compare: (Root, Root) -> ComparisonResult
    package init<Value: Comparable>(_ keyPath: KeyPath<Root, Value>, ascending: Bool = true) { … }
}
listings.sorted(by: [.init(\.rating, ascending: false), .init(\.nightlyPrice)])

static func updating<Root, Value>(_ root: Root, _ kp: WritableKeyPath<Root, Value>, to value: Value) -> Root

static var hostName: KeyPath<Listing, String> { (\Listing.host).appending(path: \Host.name) }
static let titlePath: KeyPath<Listing, String> & Sendable = \Listing.title
```

**Finding:** `static let hostName = (\Listing.host).appending(path: \Host.name)` is rejected in Swift 6: *"static property 'hostName' is not concurrency-safe because non-'Sendable' type 'KeyPath<…>'…"*. `KeyPath` is a class and isn't `Sendable` in general. Only a **literal** can be typed `KeyPath<…> & Sendable` (SE-0418), and `appending` returns a plain `KeyPath`. The appended key path also equals the literal `\Listing.host.name` (tested).

**Interview drill**

- **The hierarchy?** `AnyKeyPath` → `PartialKeyPath<Root>` → `KeyPath<Root, Value>` → `WritableKeyPath` → `ReferenceWritableKeyPath`. The reference version is separate because writing through a class root mutates the *object*, not the variable. So `obj[keyPath:] = v` is nonmutating and needs no `inout` root, and a different subscript overload applies.
- **Key paths and `Sendable` in Swift 6?** SE-0418: a key-path literal is inferred `Sendable` when everything it captures (subscript arguments) is `Sendable`, and you can spell it `KeyPath<R, V> & Sendable`. Key paths built at runtime (`appending`) aren't `Sendable`. This matters for storing them in globals and for passing them across actors.
- **Where do they show up?**
  - SwiftUI: `ForEach(items, id: \.id)`, `@Environment(\.colorScheme)`, and `$model.title`, a `Binding` built through `@dynamicMemberLookup` with `WritableKeyPath`.
  - SwiftData: `SortDescriptor(\.title)` and `#Predicate`.
  - `@Observable`: the macro-generated `access(keyPath:)` and `withMutation(keyPath:)` track reads and writes per key path.

---

## 10. Custom sequences and lazy evaluation

**Theory.**
- A `Sequence` can be iterated, maybe only once; a `Collection` adds multi-pass iteration and indices.
- `lazy` wraps a sequence so `map`/`filter` return lazy views that compute elements on demand, every time you iterate.
- `LazySequenceProtocol` is what keeps a custom adapter lazy.

**Solution:** [E10_LazySequences.swift](../Sources/Language/E10_LazySequences.swift)

```swift
struct StayNights: Sequence {               // calendar.date(byAdding: .day, …), never + 86_400
    struct Iterator: IteratorProtocol { var upcoming: Date?; … }
}
struct PriceSeries: Sequence, IteratorProtocol { … }   // infinite

struct LazyChunkedSequence<Base: Sequence>: LazySequenceProtocol { … }
extension LazySequenceProtocol {
    func chunked(by size: Int) -> LazyChunkedSequence<Elements> { … }
}
```

**Verified with exact counts:**
- `PriceSeries().lazy.filter{>100}.map{*2}.prefix(4)` runs the filter **14 times** (days 0…13, weekends are 5, 6, 12 and 13) and the map **4 times**. An eager `filter` on an infinite sequence never returns.
- Iterating a lazy `map` twice runs the closure **6 times** for 3 elements: lazy is not cached.
- DST: from 2026-03-07 to 03-10 in New York, every night stays at 00:00. The naive `+ 2×86_400` lands at **01:00**.
- I hit a compile error on the first try: a stored property named `next` collides with `next()` (*"invalid redeclaration of 'next()'"*). The property is now `upcoming`.

**Interview drill**

- **`Sequence` vs `Collection`?** `Collection` adds non-destructive multi-pass iteration, `startIndex`/`endIndex`, a subscript by index, slicing (`SubSequence`) and `count`. `count` is O(1) only for `RandomAccessCollection`; for a plain `Collection` it's O(n).
- **When does `lazy` hurt?**
  1. When the result is iterated more than once: the work is redone every time.
  2. With no early exit, when the eager version would be simpler and is equally fast.
  3. **Lazy filter collections:** index operations (`startIndex`, `index(after:)`, `count`) re-run the predicate. In the capstone, `Array(lazy.filter(p).prefix(1))` called `p` **6 times** to return 1 element.
  4. Lazy adapters store closures (escaping), which costs allocations and blocks some optimizations.
- **`some Sequence<Date>` vs `AnySequence<Date>`?** Prefer `some Sequence<Date>`: it hides the concrete type and still lets the compiler specialize and inline, with no box and no dynamic dispatch on `next()`. Use `AnySequence` only when you must store values of different underlying types, or return different types from different branches.
- **`first(where:)` and lazy?** `first(where:)` already stops at the first match on *any* sequence, so `.lazy.filter(p).first` gains nothing over `first(where: p)`. But `.lazy.map(f).first` calls `f` once, while `map(f).first` maps every element first.

---

# Tier 3: Protocols and generics

## 11. Associated types and primary associated types

**Theory.** An associated type is a placeholder that each conforming type fills in: an *output* of the conformance. A primary associated type (SE-0346) is the one you can constrain with angle brackets: `some Repository<Listing>`, `any Collection<Int>`.

**Solution:** [E11_AssociatedTypes.swift](../Sources/Language/E11_AssociatedTypes.swift)

```swift
package protocol Repository<Entity> {
    associatedtype Entity: Identifiable
    associatedtype Entities: Collection = [Entity] where Entities.Element == Entity
    func all() -> Entities
    func find(_ id: Entity.ID) -> Entity?
    mutating func upsert(_ entity: Entity)
}
package struct InMemoryRepository<E: Identifiable>: Repository { … }        // insertion order, O(1) lookup
package struct SortedRepository<E: Identifiable & Comparable>: Repository { … }  // binary-search insert
static func makeListingRepository(_ l: [Listing] = []) -> some Repository<Listing>

extension Repository { func duplicates<Key: Hashable>(by: KeyPath<Entity, Key>) -> [Key: [Entity]] }
extension Repository where Entity: Hashable { func entitySet() -> Set<Entity> }
```

One generic test helper (`func exercise<R: Repository<Listing>>(_ r: inout R)`) runs the same contract against all three implementations: in-memory, sorted and the opaque one. Callers of the opaque factory can use `all()` as a `Collection` of `Listing`, but can't treat it as an `Array`.

**Design note (step 5):** `Entity.ID` is not a separate primary associated type. It's fully determined by `Entity` (through `Identifiable`). Making it primary would add a redundant knob that can only contradict `Entity`.

**Interview drill**

- **Why couldn't you write `let r: Repository` before Swift 5.7?** Protocols with associated types or `Self` requirements could only be generic constraints (*"can only be used as a generic constraint because it has Self or associated type requirements"*). SE-0309 allowed existentials for all protocols, SE-0335 made the spelling `any P`, and SE-0346/SE-0353 added `any Repository<Listing>`.
- **How do you choose the primary one?** It's the associated type that callers constrain most often, and that is part of what the protocol *means*: `Collection<Element>`, not `Index`; `Repository<Entity>`, not `Entities`.
- **Why associated types instead of generic protocols?** A type conforms to a protocol **at most once**, and its associated types are determined by that one conformance. That keeps conformance lookup unique (dynamic casts, witness tables) and type inference tractable. A generic protocol like `Repository<T>` would let one type conform many times (Rust-style), and every use would have to spell `T`. Primary associated types give the convenient syntax without giving up uniqueness.

---

## 12. `some` vs `any`

**Theory.**
- `some P` is **one** concrete type, hidden but fixed. In return position the implementation chooses it; in parameter position the caller does (it's sugar for a generic parameter). It's statically dispatched and can be specialized.
- `any P` is a **box** (an existential container) that can hold any conforming type, which can change at runtime. Calls go through the witness table, and values that don't fit the 3-word inline buffer are heap-allocated.

**Solution:** [E12_SomeVsAny.swift](../Sources/Language/E12_SomeVsAny.swift)

```swift
// error: …declares an opaque return type 'some P', but the return statements
//        in its body do not have matching underlying types        (verified)
static func anyStrategy(for season: Season) -> any PricingStrategy { … }    // fix A
static func someStrategy(for season: Season) -> some PricingStrategy {      // fix B: one wrapper type
    SeasonalPricing(kind: .surge(…))
}
static func auditExistential(_ s: any PricingStrategy) -> String { audit(s) }  // implicit opening

// Swift 6.4 shorthand (SE-0521)
static func optionalQuote(_ s: any PricingStrategy?, nights: Int) -> Decimal?
static func optionalQuoteOpaque(_ s: some PricingStrategy?, nights: Int) -> Decimal?
static func optionalSendableQuote(_ s: any (PricingStrategy & Sendable)?, nights: Int) -> Decimal?
```

**Memory layout (tested, 64-bit):**

| Type | Size | Why |
| --- | --- | --- |
| `any PricingStrategy` | **40** | 3-word inline value buffer + type metadata pointer + 1 witness table |
| `(any PricingStrategy)?` | **40** | `nil` uses an extra inhabitant (the metadata pointer can't be null), so there's no extra byte |
| `any PricingStrategy & AnyObject` | **16** | class reference + witness table: no inline buffer needed |
| `StandardPricing` | 20 (`Decimal`) | the concrete value, no box |

Erased PAT (step 4): with `any Repository<Listing>`, `Entity` is known. `all()` is covariantly erased to `any Collection<Listing>`, and the `mutating upsert` still works on an `inout` existential (the compiler opens the box in place).

**Interview drill**

- **"Use `some` by default, `any` when you need heterogeneity." Defend or refine.** Mostly right; I'd refine it:
  - Prefer `some` or generics for parameters and returns (specialization, no boxing).
  - Use `any` for heterogeneous collections, stored properties whose concrete type is chosen at runtime (dependency injection), and to avoid generic explosion across module or API boundaries, where it can make the API simpler.
  - `any` also loses information: associated types get erased, and you can't call `Self`-returning members without opening.
  - An opaque `some` return lets a resilient library change the underlying type without breaking clients.
- **What if the value doesn't fit the inline buffer?** It's allocated in a reference-counted heap box, and the existential stores a pointer. Copying the existential just retains the box, and mutating through it copies the box first (copy-on-write), so you keep value semantics but pay an allocation.
- **Who chooses the concrete type?** In return position, the **callee** (the implementation) picks it and the caller only sees "some P". In parameter position, the **caller** picks it: `func f(_ x: some P)` is exactly `func f<T: P>(_ x: T)`.

---

## 13. Generic constraints and constrained extensions

**Theory.** `where` clauses add requirements, and constrained extensions add members only when those requirements hold. The key point is that **overloads are resolved at compile time**, using what the compiler knows *at the call site*. Only protocol **requirements** are dispatched dynamically.

**Solution:** [E13_GenericConstraints.swift](../Sources/Language/E13_GenericConstraints.swift)

```swift
extension Collection where Element: AdditiveArithmetic { func sum() -> Element }
extension Sequence where Element == Listing { func averagePrice() -> Decimal }
func mergeUnique<A: Sequence, B: Sequence>(_ a: A, _ b: B) -> [A.Element]
    where A.Element == B.Element, A.Element: Hashable

extension Collection where Element: Comparable { func median() -> Median<Element> }             // "Collection"
extension RandomAccessCollection where Element: Comparable { func median() -> Median<Element> } // "RandomAccessCollection"

// The trap: inside a generic over `C: Collection`, the call resolves to the Collection overload
static func report<C: Collection>(_ c: C) -> Median<C.Element> where C.Element: Comparable { c.median() }

// The fix: a customization point (requirement + defaults; the most specific default is bound at conformance)
protocol MedianComputable: Collection where Element: Comparable { func fastMedian() -> Median<Element> }
extension MedianComputable { … "Collection" }
extension MedianComputable where Self: RandomAccessCollection { … "RandomAccessCollection" }
extension Array: E13.MedianComputable where Element: Comparable {}
```

| Call | Overload that runs |
| --- | --- |
| `[5, 1, 3].median()` | RandomAccessCollection |
| `report([5, 1, 3])` | **Collection** (the trap) |
| `reportFixed([5, 1, 3])` | RandomAccessCollection |
| `reportFixed(Set(...))` | Collection |

(While writing the tests, I found that `[1.5, 2.5].sum() == 4` is an *"ambiguous use of operator '=='"*, because Foundation brings in many literal-convertible candidates. Writing `[1.5, 2.5] as [Double]` fixes it.)

**Interview drill**

- **Overloads vs customization points, with `count` and `underestimatedCount`.** `count` is a `Collection` **requirement**. Its default walks the collection in O(n), and random-access types supply an O(1) witness. A generic algorithm over `C: Collection` therefore still gets O(1) for an `Array`. `underestimatedCount` is a `Sequence` requirement for the same reason: `Array(someSequence)` can reserve capacity in generic code. If they were plain extension methods, generic code would always run the slow default, exactly like `report` above.
- **What is specialization, and when can't the optimizer do it?** Specialization means generating a copy of the generic function for a concrete type, so witness-table calls become direct, inlinable calls. It needs the function **body**. Across module boundaries, the body is only available if the function is `@inlinable` (or CMO is on: SwiftPM release builds pass `-enable-default-cmo`, which I saw in the build log). Otherwise the generic code runs unspecialized, through metadata and witness tables.

---

## 14. Conditional conformance and phantom types

**Theory.** A conditional conformance makes a generic type conform to a protocol only when its parameters do (`Array: Equatable where Element: Equatable`). A phantom type parameter is never stored. It exists only so the type checker can tell two otherwise identical types apart.

**Solution:** [E14_ConditionalConformance.swift](../Sources/Language/E14_ConditionalConformance.swift)

```swift
package struct Tagged<Tag, RawValue> { package let rawValue: RawValue }
package typealias ListingID = Tagged<Listing, UUID>

extension Tagged: Equatable where RawValue: Equatable {}
extension Tagged: Hashable where RawValue: Hashable {}
extension Tagged: Sendable where RawValue: Sendable {}       // Tag isn't stored, so it doesn't matter
extension Tagged: Comparable where RawValue: Comparable { … }
extension Tagged: Decodable where RawValue: Decodable {       // the bare value, not {"rawValue": …}
    package init(from decoder: any Decoder) throws { self.init(try decoder.singleValueContainer().decode(RawValue.self)) }
}
// ExpressibleByStringLiteral needs the whole chain: UnicodeScalar → ExtendedGraphemeCluster → String
```

Verified:
- `ListingID` encodes as `"5F1B6C1E-…"` and round-trips.
- `Set<ListingID>` deduplicates.
- `MemoryLayout<Tagged<Listing, UUID>>.size == MemoryLayout<UUID>.size` (the phantom type is free).
- Passing a `ListingID` where a `HostID` is expected: *"cannot convert value of type 'Tagged<ListingTag, Int>' to expected argument type 'Tagged<HostTag, Int>'"*.
- Bonus: `extension Optional: PricingStrategy where Wrapped: PricingStrategy` compiles, and `nil.price(nights: 3) == 0`. That's a **free stay**, which is exactly why you shouldn't ship it.

**Interview drill**

- **What's a phantom type and what does it cost?** A generic parameter that appears in the type but in no stored property. It costs nothing at runtime (same layout, tested). It moves "don't mix listing IDs and host IDs" from code review to the compiler.
- **Why can't a type conform twice with different conditions?** Conformances must be unique: a type has at most one witness table per protocol. `as? P` and generic dispatch must find *the* conformance unambiguously. So `extension Array: P where Element == Int` plus `extension Array: P where Element == String` is a "conflicting conformance" error. You'd need a wrapper type, or a protocol on `Element` instead.
- **Are conditional conformances resolved at runtime in dynamic casts?** Yes. `(id as Any) as? any Hashable` succeeds because the runtime checks the condition (`UUID: Hashable`) and builds the conditional witness table on demand. `Tagged<Listing, NotHashable>` fails the same cast (both are tested).

---

## 15. Type erasure

**Theory.** Type erasure hides a concrete type behind a uniform one. Modern Swift often doesn't need hand-written erasers, because `any EventSink<Event>` is built in. You still need one when the erased type itself must **conform to protocols** (existentials don't), or when you need control over semantics or representation.

**Solution:** [E15_TypeErasure.swift](../Sources/Language/E15_TypeErasure.swift)

```swift
package protocol EventSink<Event> { associatedtype Event; mutating func send(_ event: Event) }

// 1. Closure-based, Hashable by identity (ObjectIdentifier for class sinks, a UUID token for value sinks)
package struct AnyEventSink<Event>: EventSink, Hashable { … }

// 2. Class-box + subclass ("hand-written witness table") with copy-on-write on the box
struct BoxedEventSink<Event>: EventSink {
    private class _Box { func send(_: Event); func copy() -> _Box }
    private final class _ConcreteBox<S: EventSink>: _Box where S.Event == Event { var sink: S }
    package mutating func send(_ e: Event) {
        if !isKnownUniquelyReferenced(&box) { box = box.copy() }
        box.send(e)
    }
}
```

**What step 4 showed** (a stateful *struct* sink, copied after erasure, then each copy sends one event):

| Strategy | Reported counts | Semantics |
| --- | --- | --- |
| Closure eraser | `[1, 2]` | **shared** state: the closure captures one `var` box |
| Class box + CoW | `[1, 1]` | value semantics |
| `any EventSink<…>` | `[1, 1]` | value semantics (the existential copies the value) |

`Set<AnyEventSink<…>>` deduplicates the same object, while `Set<any EventSink<…>>` is an error, because `any EventSink` can't conform to `Hashable`.

**Interview drill**

- **How does `AnyHashable` / `AnySequence` work internally?** A small box hierarchy: a protocol or base class that defines the operations, plus a generic concrete box that stores the value and forwards to its real implementation. `AnyHashable` stores a `_AnyHashableBox` existential that holds the base value and its `==`/`hash`. It also special-cases bridged numbers, so `AnyHashable(1) == AnyHashable(1.0 as NSNumber)`. `AnySequence` boxes the base sequence and its iterator the same way.
- **Why is `any Error` allowed where `E: Error` is expected?** `Error` **self-conforms**: it has no static requirements, initializers or associated types, so the existential can safely stand in for a conforming type. The compiler special-cases it (and `@objc` protocols without static requirements). Other protocols' existentials don't conform to themselves.
- **In a public SDK: `AnyEventSink` or `any EventSink<E>`?** `any EventSink<E>` adds no API surface and is enough if clients just call `send`. A wrapper struct can **conform** to things (`Hashable`, `Sendable`, `Codable`), add identity or metadata, and change its internal representation later without breaking clients (a resilient struct). In a library with ABI stability or long-term evolution, I'd ship the wrapper when conformances matter; otherwise `any`.

---

## 16. Parameter packs

**Theory.** `each T` declares a *type pack*, and a parameter of type `repeat each T` is a *value pack*. `repeat <pattern>` expands the pattern once per element, and inside it `each x` means "the current element". `(repeat each T)` is a tuple of the pack. Every element stays statically typed: no `Any`, no casts. Packs arrived in Swift 5.9 (SE-0393/0398/0399), with pack iteration in 6.0 (SE-0408).

**Solution:** [E16_ParameterPacks.swift](../Sources/Language/E16_ParameterPacks.swift)

```swift
// Typed `if let a, let b, …` for any arity. A `repeat` expression can't return early, so a throwing helper aborts it.
static func allPresent<each T>(_ values: repeat (each T)?) -> (repeat each T)? {
    do { return (repeat try unwrap(each values)) } catch { return nil }
}

// One zip for any number of sequences. Iterators live in reference boxes,
// because you can't mutate elements of a tuple pack in place.
static func zipAll<each S: Sequence>(_ s: repeat each S) -> [(repeat (each S).Element)] {
    let boxes = (repeat IteratorBox((each s).makeIterator()))
    var result: [(repeat (each S).Element)] = []
    while let row = allPresent(repeat (each boxes).next()) { result.append(row) }
    return result
}

package struct FormValidator<each Field> {
    package let rules: (repeat Rule<each Field>)
    package func failures(_ values: repeat each Field) -> [String] {
        var failed: [String] = []
        func check<V>(_ rule: Rule<V>, _ value: V) { if !rule.isValid(value) { failed.append(rule.name) } }
        repeat check(each rules, each values)   // pairs the i-th rule with the i-th value
        return failed
    }
}

for value in repeat each values { descriptions.append(value.description) }   // pack iteration
```

Tested at arities 1, 2, 3 and 5. A pack of one element *is* the element: `allPresent(5)` returns `Int?`, not a 1-tuple.

**Interview drill**

- **What do packs solve that `[Any]` and overload families don't?** Arbitrary arity **and** full static typing. Overload families stop at some N (SwiftUI used to stop at 10 views) and multiply code. `[Any]` loses types and needs runtime casts.
- **Type pack vs value pack, and what does `repeat` expand?** `each T` in the generic parameter list is a type pack (a list of types). `_ v: repeat each T` is a value pack (a list of values of those types). `repeat P` is a pack expansion: it instantiates pattern `P` once per element, substituting the current element wherever `each` appears. It works in types (`(repeat each T)`), expressions (`repeat check(each a, each b)`) and `for … in repeat each`.
- **Where do packs appear in frameworks?** SwiftUI's `ViewBuilder.buildBlock<each Content: View>` (iOS 17+) replaced the 10-overload family (which is why the 10-view limit is gone), and so did `TupleView`. Foundation's `#Predicate<each Input>` uses packs too.

---

# Tier 4: Errors and data

## 17. `Result` as a value

**Theory.** `throws` is how failures *flow* through code. `Result<Success, Failure>` is a failure turned into a *value*: something you can store, pass to a callback, collect and transform. Since SE-0413, `Result.get()` is `throws(Failure)`, and `Result(catching:)` keeps a typed error.

**Solution:** [E17_Result.swift](../Sources/Language/E17_Result.swift)

```swift
extension Result {
    func zip<Other>(_ other: Result<Other, Failure>) -> Result<(Success, Other), Failure>
    static func collect(_ thunks: [() -> Result<Success, Failure>]) -> Result<[Success], Failure>  // fail fast
    func recover(_ f: (Failure) -> Success) -> Result<Success, Never>
}

// Bridge to async WITHOUT erasing the error type.
// (withCheckedThrowingContinuation would erase it to `any Error`.)
package func fetchListing(id: ListingID) async throws(ListingError) -> Listing {
    let result = await withCheckedContinuation { (c: CheckedContinuation<Result<Listing, ListingError>, Never>) in
        fetchListing(id: id) { c.resume(returning: $0) }
    }
    return try result.get()
}

Result { () throws(ListingError) -> Listing in try validatePrice(listing) }   // Result<Listing, ListingError>
```

The tests check that `collect` stops after **2 of 3** thunks, that `recover(...).get()` needs no `try`, and that the async bridge is caught by an exhaustive `switch` over `ListingError` with no `default`.

**When `Result` still beats `throws` in Swift 6:**
- storing outcomes (a cache or memo of successes *and* failures);
- batch processing where you keep every outcome instead of stopping at the first error;
- callback and legacy boundaries;
- passing an outcome across an API that can't throw (a delegate, a notification);
- accumulating errors for a report.

**Interview drill**

- **`Result<T, any Error>` vs `throws`: which composes better?** `throws`: propagation is automatic with `try`, with no `map`/`flatMap` nesting and no pyramid of `switch` statements, and it works with `async`, `defer` and `rethrows`/typed generics. `Result` composes better only when the outcome must be a value.
- **Why doesn't `Result<_, Never>.get()` need `try`?** `get()` is declared `throws(Failure)`, and `throws(Never)` *is* non-throwing, so the compiler knows the call can't fail.

---

## 18. Typed throws

**Theory.** `throws(E)` declares the exact error type (SE-0413, Swift 6.0).
- `throws` is the same as `throws(any Error)`, and a non-throwing function is the same as `throws(Never)`.
- Generic code can carry the error type through, so `rethrows` is no longer needed.
- Errors are **never converted implicitly**: crossing from one error domain to another must be written out.

**Solution:** [E18_TypedThrows.swift](../Sources/Language/E18_TypedThrows.swift)

```swift
do throws(ListingError) { try validate(listing); return "valid" }
catch { switch error { case .notFound: …; case .invalidPrice(let p): …; case .unavailable: … } }  // no default

static func book(…) throws(BookingError) -> Confirmation {
    do { try validate(listing) } catch { throw .listing(error) }   // explicit mapping
    do { try charge(token, amount) } catch { throw .payment(error) }
    …
}

package static func withRetry<T, E: Error>(attempts: Int, _ op: () throws(E) -> T) throws(E) -> T
let value = E18.withRetry(attempts: 3) { 42 }     // E == Never: no `try` (tested)

static func mapAll<T, U, E: Error>(_ v: [T], _ f: (T) throws(E) -> U) throws(E) -> [U]   // replaces rethrows
```

If you forget the explicit mapping: *"thrown expression type 'ListingError' cannot be converted to error type 'BookingError'"* (verified).

**Design memo (≤10 lines).** Use typed throws for **closed, stable error domains** that callers handle exhaustively:
- a parser, a validator, an internal module's domain errors;
- **generic propagation** (`withRetry`, `mapAll`), where the error type should flow through unchanged;
- Embedded Swift (no `any Error` boxing);
- hot paths that shouldn't allocate an existential.

Keep untyped `throws` for public APIs whose failure modes may grow, and for anything wrapping I/O or system errors: `throws(MyError)` is a **contract**, and adding a failure mode later breaks every exhaustive `catch` (source-breaking).

**Interview drill**

- **What are `throws`, `throws(any Error)` and `throws(Never)` equal to?** `throws` ≡ `throws(any Error)`. `throws(Never)` ≡ not throwing at all.
- **Typed throws with `async let` / `TaskGroup`?** At the task boundary the type is erased to `any Error`: the throwing task-group APIs and `Task` initializers work with `Failure == any Error`. Inside a single async function, `throws(E)` works fine. At concurrency boundaries you re-map (`catch let e as ListingError`), or carry a `Result<T, E>` as the child task's value, which is the trick from Ex 17.
- **How do you evolve a public `throws(ListingError)` API when you need a new failure mode?** Adding an enum case breaks clients' exhaustive `catch` (and in resilient libraries, non-frozen enums need `@unknown default` anyway). Options:
  - plan for it with an extensible error: a struct with a `code`, or SE-0487 `@extensible` enums;
  - add a new API with the bigger error type and deprecate the old one;
  - use untyped `throws` from the start for public surfaces.

  Changing the thrown type is source- and ABI-breaking.

---

## 19. Advanced `Codable`

**Theory.** Synthesized `Codable` maps properties 1:1 to keys. Anything else is handwritten:
- nested containers (to flatten or nest);
- custom per-field decoding (string → `Decimal`, several date formats);
- polymorphism (a discriminator key);
- resilience (unknown values);
- context passed through `userInfo`.

**Solution:** [E19_Codable.swift](../Sources/Language/E19_Codable.swift)

```swift
let location = try container.nestedContainer(keyedBy: LocationKeys.self, forKey: .location)
latitude = try location.decode(Double.self, forKey: .lat)            // flattened

let amountText = try priceContainer.decode(String.self, forKey: .amount)
guard let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) … else {
    throw DecodingError.dataCorruptedError(forKey: .amount, in: priceContainer, debugDescription: …)
}   // codingPath == ["price", "amount"] (tested)

let fallback = decoder.userInfo[E19.defaultCurrencyKey] as? String ?? "USD"

switch try container.decode(String.self, forKey: .type) {
case "text": … case "photo": … case "amenities": …
default: self = .unknown(type: type)   // "video_tour" doesn't fail the payload
}
```

The date formatters are created per call: `DateFormatter` isn't `Sendable`, and a shared mutable formatter would be a data race in Swift 6.

The tests cover a golden decode (exact `Decimal`, both dates as exact epoch values), a round trip to an equal model with the same JSON shape (nested `location`, `amount` as a string), the error path for a malformed price, and the `userInfo` currency fallback.

**Interview drill**

- **`convertFromSnakeCase` vs explicit `CodingKeys` with acronyms?** `listing_url` becomes `listingUrl`, not `listingURL`, so the key isn't found and decoding fails (or silently yields `nil` for optionals). Explicit `CodingKeys` (`case listingURL = "listing_url"`) are exact and greppable.
- **Keeping a long-lived app resilient to server enum additions?** Decode unknown values into an `.unknown(raw)` case instead of throwing; use lossy decoding for arrays (skip bad elements); never `fatalError` on unexpected data; keep the raw value for logging. Treat the server as an independent component that ships changes your app has never seen.
- **Where does synthesized `Codable` come from, and why isn't it a macro?** It's a **derived conformance** built into the compiler (like `Equatable`/`Hashable`), added in Swift 4, years before macros (5.9). It also needs semantic information (each property's type and whether it is `Codable`), while macros only see syntax. A macro version would have to guess.

---

# Tier 5: Advanced language features

## 20. Scoped warning control with `@diagnose` (Swift 6.4)

**Theory.**
- Warnings belong to **diagnostic groups** (`DeprecatedDeclaration`, `ExclusivityViolation`, …).
- Module-wide control: compiler flags `-Werror <group>` / `-Wwarning <group>` (SE-0443, 6.1), or SwiftPM `.treatAllWarnings(as:)` / `.treatWarning(_:as:)` (SE-0480, 6.2).
- Per-declaration control: Swift 6.4 adds `@diagnose(Group, as: error|warning|ignored, reason: "…")` (SE-0522). It applies to that declaration's signature and body, can be nested, and **cannot affect real errors**.

**Solution:** [Sources/Migration/LegacyListingAdapter.swift](../Sources/Migration/LegacyListingAdapter.swift). The `Migration` target is built with `.treatAllWarnings(as: .error)` on 6.4.

```swift
@diagnose(DeprecatedDeclaration, as: warning, reason: "Remove after SwiftMigrator batch 3")
struct LegacyListingAdapter: Sendable {
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Bridge for callers not yet on async")
    func fetch(_ id: ListingID, completion: …) { api.fetchListingLegacy(id: id, completion: completion) }
}
```

**Each variant built and recorded on 6.4.2:**

| Variant | Compiler output |
| --- | --- |
| no `@diagnose` | `error: 'fetchListingLegacy(id:completion:)' is deprecated: Use the async version [#DeprecatedDeclaration]` |
| type-level `as: warning` only | the same message as a **warning** (the build succeeds) |
| nested `as: error` | back to an **error** inside that method |
| nested `as: ignored` (shipped) | nothing |
| `@diagnose(…, as: ignored)` on `func broken() -> Int { "not an int" }` | still `error: cannot convert return expression of type 'String' to return type 'Int'` |

The group name came from the `[#DeprecatedDeclaration]` suffix that `-print-diagnostic-groups` adds. Step 6 is [`scripts/diagnose-report.sh`](../scripts/diagnose-report.sh), which prints every escape hatch as a migration-debt table. That only works because `reason:` must be a static string.

```
| Sources/Migration/LegacyListingAdapter.swift:15 | DeprecatedDeclaration | warning | Remove after SwiftMigrator batch 3 |
| Sources/Migration/LegacyListingAdapter.swift:26 | DeprecatedDeclaration | ignored | Bridge for callers not yet on async |
| Sources/StayKit/Legacy.swift:61                 | DeprecatedDeclaration | ignored | StayKit legacy bridge: remove after SwiftMigrator batch 4 |
```

Compatibility: `@diagnose` doesn't exist on 6.3. In StayKit it's wrapped in `#if compiler(>=6.4)` *around the attribute* (SE-0367), and Package.swift only turns on warnings-as-errors on 6.4.

**Interview drill**

- **Why is scoped warning control better than `-suppress-warnings` or a module-wide `-Wwarning`?** It's **precise**: one declaration, one group, while the rest of the module stays strict, so new warnings elsewhere still fail the build. It's **self-documenting**, because the `reason:` lives next to the code. And it's **auditable**: tools can list it, count it and fail CI when it grows. Module-wide flags hide every future warning in that group, and `-suppress-warnings` hides everything.
- **Diagnostic groups as a CI ratchet during a migration?**
  1. Turn on `-warnings-as-errors` for the module.
  2. Wrap each known offender in `@diagnose(Group, as: warning, reason: "<ticket>")`.
  3. In CI, count escapes per group (the report script) and **fail if the count goes up**; the migration agent's job is to make it go down.
  4. When a group reaches zero, delete its escapes and the warning becomes a hard error forever.

---

## 21. Property wrappers

**Theory.** `@Wrapper var x` turns into stored `_x: Wrapper<T>` plus a computed `x` that goes through `_x.wrappedValue`, and `$x` maps to `_x.projectedValue`. Composition `@A @B var x` stores `A<B<T>>` and applies the wrappers **inside-out**. Wrappers also work on function parameters (SE-0293).

**Solution:** [E21_PropertyWrappers.swift](../Sources/Language/E21_PropertyWrappers.swift)

```swift
@propertyWrapper package struct Clamped<Value: Comparable & Sendable>: Sendable {
    package init(wrappedValue: Value, _ range: ClosedRange<Value>)       // clamps on init
    package var wrappedValue: Value { get set }                          // clamps on set
    package private(set) var projectedValue: ClampReport<Value>          // $guests
}

// Composition needs generic wrappers: the outer wrapper's wrapped value IS the inner wrapper
package protocol TextBox: Sendable { var text: String { get set } }
@propertyWrapper package struct Trimmed<Value: TextBox>: TextBox { … }
@propertyWrapper struct NonEmpty<Value: TextBox>: TextBox { … }
```

**Composition order (tested):** with `"   "`, `@Trimmed @NonEmpty` produces **`""`**: `NonEmpty` keeps `"   "` (not empty), then `Trimmed` trims it, breaking `NonEmpty`'s invariant. `@NonEmpty @Trimmed` produces **`"Untitled"`**.

**Finding:** my first version gave `"Untitled"` for *both* orders, and the test caught it. The wrappers' `text` setter went back through the inner wrapper's rule, so both invariants were re-applied whatever the order. Order only matters when the outer wrapper changes the inner value through a raw channel. Lesson: an outer wrapper treats the inner one as an opaque value, and can break its rules.

`@Clamped(1...16) var guests = 20` expands to:

```swift
private var _guests = Clamped(wrappedValue: 20, 1...16)
var guests: Int { get { _guests.wrappedValue } set { _guests.wrappedValue = newValue } }
var $guests: ClampReport<Int> { _guests.projectedValue }
```

The wrapper must be a **struct**: stored inline and copied with its owner, so `GuestRequest` keeps value semantics. A class wrapper would make every copy of the owner share one value.

**Interview drill**

- **What can a wrapper not do that a macro can?** A wrapper sees one property's value, and only at runtime. It can't see the enclosing type or its other properties, can't add members or conformances, and can't apply itself to every property automatically. `@Observable` needs all of that: it instruments **every** stored property, adds a registrar, and conforms the class to `Observable`. The old `@Published` + `ObservableObject` approach needed a wrapper with a hidden enclosing-instance hook *and* a separate protocol.
- **Why can't a wrapper easily reach its enclosing instance?** It's a plain stored value with no back-reference to its owner, and for structs there's no stable owner to point to. The underscored `static subscript(_enclosingInstance:wrapped:storage:)` gives the wrapper access to the instance on each get/set, but only for **class** owners. That's how `@Published` reaches `objectWillChange`.

---

## 22. Result builders

**Theory.** A `@resultBuilder` type tells the compiler how to turn a closure's statements into a value:
- `buildExpression`: each statement;
- `buildPartialBlock` (SE-0348) or `buildBlock`: combining statements;
- `buildOptional` / `buildEither`: `if` and `switch`;
- `buildArray`: `for`;
- `buildLimitedAvailability`: `if #available`;
- `buildFinalResult`: the final value.

**Solution:** [E22_ResultBuilders.swift](../Sources/Language/E22_ResultBuilders.swift)

```swift
let query = E22.SearchQuery {
    E22.Destination("Buenos Aires")
    E22.Guests(4)
    if includePets { E22.PetsAllowed() }                                   // buildOptional
    if flexible { E22.DateRange.flexible(weeks: 2) } else { E22.DateRange(a, b) }   // buildEither
    for amenity in amenities { E22.Amenity(amenity) }                      // buildArray
    if #available(macOS 26, iOS 27, *) { E22.GlassPreview() }              // buildLimitedAvailability
    "loft"                                                                 // buildExpression(String)
}
// buildFinalResult validates: missing destination, multiple destinations, guests out of 1...16
```

What the compiler generates for `if/else` (the whiteboard answer):

```swift
let v0 = SearchQueryBuilder.buildExpression(Destination("BA"))
let v1: [QueryComponent]
if flexible { v1 = SearchQueryBuilder.buildEither(first: SearchQueryBuilder.buildExpression(DateRange.flexible(weeks: 2))) }
else        { v1 = SearchQueryBuilder.buildEither(second: SearchQueryBuilder.buildExpression(DateRange(a, b))) }
let p0 = SearchQueryBuilder.buildPartialBlock(first: v0)
let p1 = SearchQueryBuilder.buildPartialBlock(accumulated: p0, next: v1)
return SearchQueryBuilder.buildFinalResult(p1)
```

**Stretch (compile-time "one destination"):** use marker types in the partial result (`Partial<HasDestination>` vs `Partial<NoDestination>`), and provide a `buildPartialBlock(accumulated: Partial<HasDestination>, next: DestinationComponent)` overload that is `@available(*, unavailable, message: "only one destination")`. I implemented runtime validation in `buildFinalResult` instead: it's simpler and gives clearer errors. Explaining the trade-off is the interview answer.

**Interview drill**

- **Desugared `if/else`:** above.
- **Why does SwiftUI need `buildLimitedAvailability`?** SwiftUI's partial results are *typed* per branch (`_ConditionalContent<A, B>`). If a branch uses a type only available on a newer OS, that type would appear in the enclosing result type, which must be available everywhere the function is. `buildLimitedAvailability` erases the branch (SwiftUI uses `AnyView`), so the result type no longer mentions the unavailable type.
- **Builders vs plain arrays?** You gain declarative syntax with real control flow, type-level composition (the result type can encode structure, as in SwiftUI), and a single place to validate. The costs: the whole closure is type-checked as **one expression**, so it gets slow and diagnostics point at the wrong line; statement support is limited; and debugging is harder.

---

## 23. Macros

**Theory.** Macros are compile-time code generators, written with SwiftSyntax, that run in a **sandboxed plugin process**. They only see the *syntax* of the code they're attached to, never types. Kinds:
- **Freestanding:** `#expr` (expression), declaration.
- **Attached:** `peer`, `member`, `memberAttribute`, `accessor`, `extension`, `body`.

Macros can emit diagnostics and fix-its, and their output is always visible ("Expand Macro").

**Solution:** [Sources/LanguageMacros/LanguageMacros.swift](../Sources/LanguageMacros/LanguageMacros.swift), declarations in [Macros.swift](../Sources/LanguageMacrosClient/Macros.swift).

```swift
@freestanding(expression)
package macro listingURL(_ string: String) -> URL = #externalMacro(module: "LanguageMacros", type: "ListingURLMacro")

@attached(peer, names: overloaded)
package macro AddAsync() = #externalMacro(module: "LanguageMacros", type: "AddAsyncMacro")
```

- **`#listingURL`** checks for a static literal (no interpolation) and a valid absolute URL at compile time, and expands to `URL(string: "…")!`. The force-unwrap is safe because the URL was already validated. `http://` gets an error with a **fix-it** ("Replace 'http://' with 'https://'").
- **`@AddAsync`** is SwiftMigrator's migration done at compile time:

  ```swift
  @AddAsync
  package func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void)
  // generates:
  package func fetchListing(id: ListingID) async throws(ListingError) -> Listing {
      let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Listing, ListingError>, Never>) in
          fetchListing(id: id) { result in
              continuation.resume(returning: result)
          }
      }
      return try result.get()
  }
  ```

  It keeps modifiers, generics, `_` labels and nested generic types (`Result<[String: [Int]], any Error>`). It produces diagnostics for a non-function, a missing `completion` and a non-`Result` completion. The generic arguments are parsed from the type's *text*, because swift-syntax's generic-argument API changed between releases.
- **10 expansion tests** use `SwiftSyntaxMacrosGenericTestSupport` with a Swift Testing failure handler (`MacroSpec` lives in `SwiftSyntaxMacroExpansion`). The test harness **re-formats** expansions, so I restructured the generated code into a shape the formatter keeps.
- **`@Observable` expanded** (step 3): `@attached(member)` adds `_$observationRegistrar`, `access(keyPath:)` and `withMutation(keyPath:_:)`. `@attached(memberAttribute)` puts `@ObservationTracked` on each stored `var`. `@attached(extension, conformances: Observable)` adds the conformance. `@ObservationTracked` is itself an **accessor + peer** macro: it turns `var title` into get/set calls through the registrar, with the real storage in a peer `_title`.

**Interview drill**

- **Macros vs property wrappers vs result builders vs codegen scripts?**
  - **Wrapper:** per-property behavior at runtime (clamping, persistence).
  - **Builder:** a declarative DSL for composing values.
  - **Macro:** compile-time generation that needs the *syntax* of a declaration (all its members, signatures), with diagnostics, and stays visible and type-checked.
  - **Codegen script** (SwiftGen, Sourcery, OpenAPI): needs whole-project, cross-file or non-Swift inputs (assets, specs), and its output is checked in.
- **Why sandboxed and in a separate process? What can't macros see?** Security (arbitrary code running inside your build), determinism (no network or file system, so the same input always gives the same output), and stability (a crashing macro doesn't crash the compiler). A macro sees only the syntax tree of its node plus a little lexical context. No types, no other files, no ability to know what `ListingID` *is*, which is why `@AddAsync` works on text.
- **Build cost of swift-syntax?** It's a large package. Building it from source adds minutes to clean builds and CI (the release build of this repo took about 7 minutes on an Intel i9, mostly swift-syntax). Recent SwiftPM/Xcode versions can use **prebuilt swift-syntax** binaries for macro targets instead of compiling it; otherwise, cache `.build` in CI and keep macro targets in their own package so they don't rebuild with every change.

---

# Tier 6: Ownership and performance

> Every compile error quoted in this tier is reproduced by [`scripts/verify-compile-errors.sh`](../scripts/verify-compile-errors.sh) (snippets in [`CompileFailures/`](../CompileFailures)). Several of them (`discard`, lifetimes, `mutate`) are **SIL-level** diagnostics: `swiftc -typecheck` and editor quick checks don't show them, only a real build does.

## 24. Noncopyable types: `ReservationLock`

**Theory.** `~Copyable` removes the implicit `Copyable` conformance:
- A value has **exactly one owner**.
- Assigning or passing it by value **moves** it.
- The compiler rejects any use after the move.
- Noncopyable structs and enums can have a `deinit`, which runs deterministically when the owner's lifetime ends: no reference counting, and no "some other reference keeps it alive".
- A `consuming` method takes `self`. `discard self` ends the lifetime **without** running `deinit`.

**Solution:** [E24_ReservationLock.swift](../Sources/Ownership/E24_ReservationLock.swift)

```swift
package struct ReservationLock: ~Copyable {
    package let listingID: Int
    package private(set) var token: UInt64          // only trivially-destroyed fields (see below)

    package init(acquiring listingID: Int) throws(LockError) { self.token = try LockRegistry.shared.acquire(listingID); … }

    package consuming func release() -> ReleaseReceipt {
        let receipt = registry.release(listingID, token: token, forced: false)
        discard self                               // no deinit afterwards: released exactly once
        return receipt
    }

    deinit { _ = registry.release(listingID, token: token, forced: true) }   // safety net when dropped
}

package final class LockRegistry: Sendable {
    private let state = Mutex(State())              // Synchronization; Mutex is itself ~Copyable
}
```

**The `discard` restriction (verified on 6.4.2).** My first design stored `let registry: LockRegistry`, so each test could have its own registry. A full build rejects it: *"can only 'discard' type 'Lock' if it contains trivially-destroyed stored properties at this time"*. (`swiftc -typecheck` accepted it, so the error only shows on a real build.) So the lock uses the process-wide registry, and the tests use unique listing IDs.

**Recorded compile errors (all verified):**

| Code | Error |
| --- | --- |
| `let other = lock; lock.release()` | `'lock' consumed more than once` (the `let` was the first consume) |
| `lock.release(); lock.release()` | `'lock' consumed more than once` |
| `let locks: [ReservationLock] = []` | `type 'Lock' does not conform to protocol 'Copyable'` (Array needs Copyable; Ex 30 fixes it) |
| capture in an escaping closure | `noncopyable 'lock' cannot be consumed when captured by an escaping closure or borrowed by a non-Escapable type` |

**vs a `final class` lock with `deinit`:** a class lock can be shared (two references to one lock), so "who releases it?" is unclear. Its `deinit` runs when the *last* reference anywhere disappears, it costs a heap allocation plus reference counting, and it can be captured and escape. The noncopyable lock costs no allocation, cleanup happens exactly at the end of its scope, and misuse is a compile error.

**Interview drill**

- **What does `~Copyable` guarantee that a class with `deinit` can't?**
  - Unique ownership checked at compile time.
  - No implicit copies.
  - Deterministic destruction at the end of the owner's scope or last use.
  - No refcount traffic and no allocation.
  - Use-after-move and double-consume are *compile* errors.

  A class guarantees none of these.
- **Where is this pattern used?** In the standard library: `Mutex` and `Atomic` (Synchronization), and `UniqueBox`/`UniqueArray` (6.4). `Span` is the sibling concept: it's `~Escapable` rather than `~Copyable`. In app code it fits single-use resources: file handles, database transactions, payment tokens and reservations (this repo).

---

## 25. `borrowing`, `consuming`, `inout`, `consume` and `copy`

**Theory.** Parameter conventions:

| Convention | Who owns it during the call | Afterwards | Copies |
| --- | --- | --- | --- |
| `borrowing` | the caller | the caller still has it | no implicit copies of the parameter |
| `consuming` | the callee | the caller has lost it | — |
| `inout` | the caller, with exclusive access | the caller gets it back, possibly changed | — |

Defaults: ordinary parameters are borrowed; `init` parameters and setter `newValue` are consumed. The `consume x` operator ends a local's lifetime and forwards its value. `copy x` makes an explicit copy.

**Solution:** [E25_OwnershipModifiers.swift](../Sources/Ownership/E25_OwnershipModifiers.swift)

```swift
static func inspect(_ lock: borrowing ReservationLock) -> String
static func transfer(_ lock: consuming ReservationLock, to: String) -> Handoff
static func renew(_ lock: inout ReservationLock) { lock.rotateToken() }

static func appendingBlock(_ c: consuming AvailabilityCalendar) -> AvailabilityCalendar { c.block(0..<1); return c }
static func duplicate(_ c: borrowing AvailabilityCalendar) -> AvailabilityCalendar { copy c }
```

**Measured with the CoW calendar from Ex 06 (`_storageID` is the identity of its buffer):**

| Call | Buffer |
| --- | --- |
| `appendingBlock(consume cal)` | **same `_storageID`**: the reference moved in, stayed unique, mutated in place |
| `appendingBlock(cal)`, then `cal` used again | **different `_storageID`**: shared, so a 365-day copy |

That's the measurable proof that ownership annotations affect performance, even for Copyable types.

**Recorded errors:**
- `func duplicate(_ c: borrowing Calendar) -> Calendar { c }`: *"'c' is borrowed and cannot be consumed"*. The fix is `copy c`.
- Partial consumption (SE-0429): `Hold.takeLock()` can move `lock` out of a consuming `self` while `note` is destroyed normally. With a `deinit`: *"cannot partially consume 'self' when it has a deinitializer"*. The capstone hit a related one: after `reservation.lock.release()`, reading `reservation.id` is *"'reservation' used after consume"*. Read the Copyable fields first.

**Interview drill**

- **`consuming` vs `inout`: both let you mutate. What's different for the caller?** `inout` *borrows exclusively* and must give a valid value back: the caller keeps ownership and sees the changes. `consuming` *transfers* ownership: the caller's value is gone (for a Copyable type, the caller passes a copy unless it writes `consume`), and the callee may destroy it, store it or return something else.
- **Why are ownership modifiers on Copyable parameters ABI-affecting?** They change the **calling convention**: who retains, who releases, and who must destroy the value. Changing `borrowing` to `consuming` on a public function of a resilient library changes its ABI, so pick deliberately for API that is meant to last.
- **`consume` in terms of ARC?** Without it, passing `cal` to a consuming parameter while `cal` is still alive means a **retain** (+1, so the buffer isn't unique) and a later release. `consume cal` ends `cal`'s lifetime right there, so the existing +1 is *forwarded*: no retain/release pair, and the callee holds the only reference, which keeps CoW buffers unique.

---

## 26. Typestate with noncopyable types

**Theory.** If every state transition *consumes* the old state, a stale state can't be reused, and illegal transitions can be made unrepresentable. There are two styles: a noncopyable **enum** (one type, transitions return a result) or **typestate structs** (one type per state, so illegal transitions don't type-check).

**Solution:** [E26_Typestate.swift](../Sources/Ownership/E26_Typestate.swift)

```swift
enum Reservation: ~Copyable {
    case draft(DraftInfo)
    case confirmed(DraftInfo, paymentRef: String, lock: ReservationLock)
    case cancelled(DraftInfo, reason: String, receipt: ReleaseReceipt?)

    consuming func confirm(payment: PaymentToken) -> Transition {
        switch consume self {                      // own self → can move payloads (the lock!)
        case .draft(let info): … return .moved(.confirmed(info, paymentRef: …, lock: lock))
        case let .confirmed(info, ref, lock): return .rejected(.confirmed(info, paymentRef: ref, lock: lock), reason: …)
        …
        }
    }
    var status: String { switch self { case .draft: "draft" … } }   // borrowing switch (SE-0432)
}
enum Transition: ~Copyable { case moved(Reservation); case rejected(Reservation, reason: RejectReason) }

// B: typestate
struct DraftReservation: ~Copyable { consuming func confirm(payment:) throws(ConfirmError) -> ConfirmedReservation }
struct ConfirmedReservation: ~Copyable { consuming func cancel(reason:) -> CancelledReservation }
struct CancelledReservation: Hashable, Sendable { … }   // terminal → Copyable
```

**Why not `throws` in A?** `Error` requires `Copyable` (and `Sendable`), so a thrown error can't carry the noncopyable reservation back to the caller. A failed *consuming* transition must **return** the value (`.rejected(reservation, reason:)`). In B, `ConfirmError` carries the Copyable `DraftInfo`, so the caller can rebuild a draft.

**Comparison memo.** B moves *legality* checks to compile time: `draft.cancel()` is *"value of type 'Draft' has no member 'cancel'"*, and cancelling twice is *"consumed more than once"*. B loses heterogeneous storage (you can't keep `[any ReservationState]` of noncopyables in an Array), easy persistence, and SwiftUI binding (views want one Copyable model). **I'd ship B inside the booking engine** (the core is where bugs cost money) and expose a Copyable `ReservationSnapshot` value at the UI and persistence edge.

**Interview drill**

- **`switch consume self` vs a borrowing `switch self`?** Use `consume` when you need to *move* payloads out (transitions: the lock goes into the next state). Use a borrowing switch (Swift 6.0, SE-0432) to *inspect* without giving up the value (`status`). Its bindings are borrows, so the value is still there afterwards.
- **Why is this better than an `enum State` plus `precondition` checks?** Preconditions turn a logic error into a **runtime crash**, possibly in production. Typestate turns it into a **compile error** (B) or into a value the compiler forces you to handle (A's `Transition`). And because the lock is *moved*, a confirmed reservation's lock can't leak or be released twice.

---

## 27. Noncopyable generics: `Box<T: ~Copyable>`

**Theory.** Every generic parameter, protocol and extension implicitly requires `Copyable`. `T: ~Copyable` *suppresses* that requirement: it means "T **may** be noncopyable", so Copyable types still qualify and the code must never copy a `T`. `extension Box: Copyable where T: Copyable {}` makes the box exactly as copyable as its contents.

**Solution:** [E27_NoncopyableGenerics.swift](../Sources/Ownership/E27_NoncopyableGenerics.swift)

```swift
struct Box<T: ~Copyable>: ~Copyable { var value: T }
extension Box: Copyable where T: Copyable {}
extension Box: Sendable where T: Sendable & ~Copyable {}

extension Box where T: ~Copyable {                 // must restate ~Copyable!
    consuming func unwrap() -> T { value }
    borrowing func withValue<R>(_ body: (borrowing T) -> R) -> R { body(value) }
    consuming func map<U: ~Copyable>(_ f: (consuming T) -> U) -> Box<U> { Box<U>(f(value)) }
}
extension Box { func peek() -> T { value } }  // implicitly `where T: Copyable`

protocol Resource: ~Copyable { consuming func close() -> ReleaseReceipt }
static func close<R: Resource & ~Copyable>(_ r: consuming R) -> ReleaseReceipt

lock.take()   // Optional.take() (SE-0437): moves the value out, leaves nil
```

The step 2 trap is verified: calling `peek()` on `Box<Lock>` gives *"referencing instance method 'peek()' on 'Box' requires that 'Lock' conform to 'Copyable'"*. In the tests, `Box<Int>` copies independently, and `Box<ReservationLock>.map { $0.release() }` releases exactly once.

**Interview drill**

- **Why make `Copyable` implicit and spell suppression `~Copyable`?** Source compatibility. Every existing generic signature (`func f<T>`, `protocol P`, `extension Array`) assumes values can be copied. Making `Copyable` opt-in would have broken all Swift code. Instead, the default stays and you *suppress* it exactly where your code is ready for noncopyable types.
- **Why is `T: ~Copyable` "may be", not "must be"?** `~` removes a requirement; it doesn't add a negative one. Swift has no negative constraints ("T must NOT conform"). Removing the requirement widens the set of allowed types to include noncopyable ones, and Copyable types still fit.

---

## 28. Noncopyable `Equatable` / `Comparable` / `Hashable` (Swift 6.4)

**Theory.** SE-0499 drops the implicit `Copyable` requirement from `Equatable`, `Comparable`, `Hashable` (and the string-conversion protocols). Requirements take `borrowing` parameters, so comparing doesn't copy or consume either side.

**Solution:** [E28_NoncopyableConformances.swift](../Sources/Ownership/E28_NoncopyableConformances.swift)

```swift
struct SecretToken: ~Copyable, Hashable { private let bytes: [UInt8] }   // == and hash SYNTHESIZED

struct APIKey: ~Copyable, Hashable {
    static func == (lhs: borrowing APIKey, rhs: borrowing APIKey) -> Bool { … }
    package func hash(into hasher: inout Hasher) { … }   // hash exactly what == compares
}
extension E27.Box: Equatable where T: Equatable & ~Copyable { … }
extension E27.Box: Hashable where T: Hashable & ~Copyable { … }
extension ReservationLock: Comparable { … }   // by token
static func earliest(_ a: borrowing ReservationLock, _ b: borrowing ReservationLock) -> UInt64
```

**What 6.4.2 actually ships (verified):**

| Feature from SE-0499 | Swift 6.4.2 |
| --- | --- |
| `Equatable`/`Comparable`/`Hashable` on `~Copyable` | ✅ (the conformance is synthesized when the fields qualify) |
| `Hasher.combine(borrowed noncopyable)` | ✅ |
| `optionalToken == nil` | ✅ (always worked, via `_OptionalNilComparisonType`) |
| `Optional == Optional` with noncopyable `Wrapped` | ❌ *"operator function '==' requires that 'Token' conform to 'Copyable'"* |
| `CustomStringConvertible` on `~Copyable` | ❌ *"type 'S' does not conform to protocol 'Copyable'"* |
| interpolation / `String(describing:)` | ❌ *"no exact matches in call to instance method 'appendInterpolation'"* |
| `Set<Token>` / `[Token: Int]` | ❌ *"does not conform to protocol 'Copyable'"* (the containers still require Copyable) |

So `SecretToken` exposes `redacted` instead of `description`. And `earliest` returns the *token*, not the lock, because the locks are borrowed and returning one would mean moving it out of the caller.

Testing gotcha: `#expect(a == b)` **doesn't compile** for noncopyable operands (*"global function '__checkBinaryOperation…' requires that 'SecretToken' conform to 'Copyable'"*), because the macro copies operands so it can print them. Evaluate into a `Bool` first: `let equal = a == b; #expect(equal)`.

**Interview drill**

- **Why `borrowing` parameters, and why is it ABI-compatible?** The requirement must work for values that can't be copied, so the operator must not take ownership (a comparison shouldn't *consume* its operands). Ordinary parameters already use the borrowed ("guaranteed") convention by default, so spelling it `borrowing` doesn't change the calling convention: existing binaries and witness tables stay valid. It only adds the rule "no implicit copies inside".
- **Why is `LosslessStringConvertible` `~Copyable` but not `~Escapable`?** Its requirement `init?(_ description: String)` *creates* a value. A `~Escapable` result needs a lifetime dependency on something, and a fresh value parsed from a `String` has nothing meaningful to depend on. That needs future lifetime features. Dropping `Copyable` is enough for the main use case (noncopyable big-integer types).

---

## 29. `InlineArray` and `Span`: the hot-path rewrite

**Theory.**
- `InlineArray<N, T>` (`[N of T]`, SE-0453/SE-0483) stores N elements **inline**: no heap, no CoW, no refcount. Copying it copies all N elements. It isn't a `Sequence`/`Collection`.
- `Span<T>` (SE-0447) is a bounds-checked, non-owning, **`~Escapable`** view of contiguous memory: it can't outlive what it borrows. `MutableSpan` is the exclusive, writable version.

**Solution:** [E29_InlineArraySpan.swift](../Sources/Ownership/E29_InlineArraySpan.swift)

```swift
package static func average(_ window: Span<Double>) -> Double {   // storage-agnostic
    var sum = 0.0
    for index in window.indices { sum += window[index] }
    return sum / Double(window.count)
}

var window: [7 of Double] = .init(repeating: 0)                  // reused, on the stack
for start in 0...(prices.count - 7) {
    for offset in 0..<7 { window[offset] = prices[start + offset] }
    averages.append(average(window.span))
}

var span = prices.mutableSpan                                     // in-place normalization
for index in span.indices { span[index] /= maximum }
```

The same `average` takes `Array.span`, `InlineArray.span` and `UniqueArray.span` (tested). `MemoryLayout<InlineArray<7, Double>>.size == 56` (7 × 8 bytes inline), while `MemoryLayout<[Double]>.size == 8` (a buffer reference).

**Benchmark** (`swift run -c release OwnershipBenchmarks`; Swift 6.4.2, `-O`, Intel i9-9980HK, macOS 26; 2,000 × 359 windows; 15 runs plus a warm-up; results go through a `blackHole`). Stable across two runs:

| Version | Median | p90 | Speed-up |
| --- | --- | --- | --- |
| New `[Double]` per window (naive) | 345 ms | 363 ms | 1× |
| One reused `[Double]` + `Span` (fair baseline) | 25.5 ms | 26.3 ms | 13.5× |
| `InlineArray` + `Span` | **1.69 ms** | 1.83 ms | **~204× vs naive, ~15× vs reused** |

Read it honestly. Most of the 200× is **removing a heap allocation per step**: the naive baseline also reallocates as `append` grows 1→2→4→8. That's why the table includes a fair baseline. `InlineArray` is still ~15× faster than the reused array: no uniqueness or capacity checks on each `append`, a fixed size the optimizer can unroll and vectorize, and no buffer indirection. Allocation counts aren't measured by this harness (Instruments → Allocations, or package-benchmark's malloc metrics, would show them). By construction: about 4 allocations per window for the naive version, 0 for the other two.

**Lifetime errors (verified on 6.4.2):**

| Code | Error |
| --- | --- |
| `func makeSpan() -> Span<Double> { let a = […]; return a.span }` | `a function cannot return a ~Escapable result` |
| `final class Cache { var window: Span<Double> }` | `the 'get' accessor cannot return a ~Escapable result` |
| capture a span in an escaping closure | `lifetime-dependent variable 'span' escapes its scope` |
| `for x in inlineArray` | `for-in loop requires '[3 of Int]' to conform to 'Iterable', which is only available in macOS 27.0 or newer` |

The last one is new in 6.4: with SE-0516, `InlineArray` conforms to `Iterable` (borrowing iteration) on macOS 27+. On earlier systems, iterate `indices` or the `span`.

**Interview drill**

- **`Span` vs `UnsafeBufferPointer`?** `Span` is bounds-checked, can't be stored or escaped (the compiler enforces its lifetime dependency on the source), and needs no manual memory management. An `UnsafeBufferPointer` can dangle, isn't bounds-checked in release and can be stored anywhere. `Span` costs the bounds checks (often hoisted or removed by the optimizer, with unchecked APIs for proven hot loops) and API design constraints: you hand out spans in a scope, you don't store them.
- **When should a hot path take `Span<T>`?** When it only needs to **read (or write, with `MutableSpan`) contiguous memory** and should accept any storage (`Array`, `ContiguousArray`, `InlineArray`, `UniqueArray`, `Data`, C buffers) without copying or generic specialization. Prefer `some Collection<T>` when the algorithm needs non-contiguous collections. Prefer `[T]` only when you need to keep or grow the array.
- **How do you prove a performance claim in code review?** Release build; warm-up; many runs; median and p90 (not a single number); `blackHole` against dead-code elimination; a **fair baseline** (the 13.5× vs 204× lesson); the same machine, power state and input; allocation counts next to time; the harness checked in so anyone can rerun it; and a CI threshold (package-benchmark) so the gain doesn't regress.
- *(from the exercise)* **When is `InlineArray` slower than `Array`?** When N is large and the value is passed, returned or stored by value: every copy copies all N elements, while `Array` copies one reference. Also when it's a stored property of a frequently copied struct, when it makes stack frames huge, or in generic code over `N` that isn't specialized.

---

## 30. `UniqueArray`, `RigidArray` and `UniqueBox` (Swift 6.4)

**Theory.** These are heap-allocated containers with **unique ownership**: no CoW, no refcount, `~Copyable` themselves. They can hold noncopyable elements.
- `UniqueArray`: growable.
- `RigidArray`: fixed capacity (SE-0527).
- `UniqueBox`: a single owned heap value with `value` (borrow/mutate), `consume()`, `clone()` for Copyable values, and a span (SE-0517).

Borrow/mutate accessors (SE-0507) expose stored values in place.

**Findings on Swift 6.4.2 (macOS 26):**
- `UniqueArray`/`UniqueBox` are in the **standard library** (no `import Containers`) and **gated to macOS 27**. The code compiles behind `@available(macOS 27, iOS 27, *)`, and the 5 runtime tests are reported as **skipped ("Requires macOS 27")**.
- **`RigidArray` isn't in 6.4.2**, so `HoldQueue` implements the same contract (fixed capacity, hand the element back when full) on top of `UniqueArray(capacity:)`.
- `deinit` can't mutate `self` (*"cannot use mutating member on immutable value: 'self' is immutable"*; SE-0544 is accepted but not implemented).
- **Optimizer crash** (see the findings table at the top): `NoncopyableStack` is compiled only in DEBUG builds until a fixed compiler ships.

**Solution:** [E30_OwningContainers.swift](../Sources/Ownership/E30_OwningContainers.swift)

```swift
@available(macOS 27, iOS 27, *)
package struct LockPool: ~Copyable {
    private var locks = UniqueArray<ReservationLock>()
    package mutating func acquire(_ id: Int) throws(LockError) { locks.append(try ReservationLock(acquiring: id)) }
    package mutating func release(listingID: Int) -> ReleaseReceipt? {
        for index in locks.indices where locks[index].listingID == listingID { return locks.remove(at: index).release() }
        return nil
    }
    package consuming func releaseAll() -> [ReleaseReceipt] { … while let lock = locks.popLast() { … } }
    package var first: ReservationLock { borrow { return locks[0] } }     // borrow accessor
    package func listingIDs() -> [Int] { for lock in locks { … } }          // borrowing for-in (Iterable)
}

struct OwnedSlot<Element: ~Copyable>: ~Copyable {
    private var storage: UniqueBox<Element>
    var value: Element { borrow { return storage.value } mutate { return &storage.value } }
}

struct NoncopyableStack<Element: ~Copyable>: ~Copyable {
    struct Node: ~Copyable { var element: Element; var next: UniqueBox<Node>? }
    private final class Chain {          // a class deinit CAN mutate its own storage → iterative drop
        var head: UniqueBox<Node>?
        deinit { var current = head.take(); while let box = current.take() { current = box.consume().next } }
    }
}
```

**Accessor rules found on 6.4.2 (full compile):**
- `mutate { return &storedProperty }` ✅ and `mutate { return &box.value }` ✅
- `mutate { return &uniqueArray[0] }` ❌ *"invalid return value from a mutate accessor"*. `borrow { return uniqueArray[0] }` is fine.
- `yielding mutate` ❌ *"only valid when experimental feature coroutine accessors is enabled"*
- a `borrow` with `_modify`/`set` instead of `mutate` ❌ *"A 'borrow' accessor can only be defined along with a 'mutate' accessor"*

Why the class-owned chain? With default destruction, each node's destructor destroys the next node, so 1M nodes means 1M nested frames and a stack overflow. Swift doesn't allow mutating `self` in a struct `deinit` yet, but a class's `deinit` can mutate its own stored properties, so it drops the nodes in a loop. The noncopyable outer struct never shares the class reference, so it's effectively unique.

**Benchmark (Ex 30 part):** the harness has the `UniqueArray` vs `Array` comparison (10M appends + in-place updates) behind `#available(macOS 27, *)`. On this macOS 26 machine it prints "skipped". Expectation to verify on macOS 27: small or no difference for `Int` (Array's uniqueness check is one well-predicted branch). The real win of `UniqueArray` is **noncopyable elements** and predictable costs, not raw speed.

**Interview drill**

- **`Array` vs `UniqueArray` vs `RigidArray` vs `InlineArray`?**

  | | growable | fixed capacity |
  | --- | --- | --- |
  | **heap** | `Array` (CoW, Copyable elements, shareable) · `UniqueArray` (unique, no CoW, `~Copyable` elements OK) | `RigidArray` (never reallocates; not in 6.4.2) |
  | **inline** | — | `InlineArray<N, T>` (no heap at all, eager copies) |

  Default to `Array`. Use `UniqueArray` for noncopyable elements or when you never want hidden copies. Use `RigidArray` for real-time or embedded code with no reallocation. Use `InlineArray` for small fixed-size hot data.
- **`UniqueBox<T>` vs `final class Box<T>` vs `indirect enum`?**
  - `UniqueBox`: one allocation, **no refcount**, noncopyable (moves only), destroyed deterministically, `Sendable` if `T` is.
  - `final class`: allocation plus refcounting, shared **reference** semantics and identity, needs `Sendable` care.
  - `indirect enum`: a refcounted box shared *immutably* between copies, value semantics, enums and Copyable payloads only.
- **Why isn't `UniqueArray` `ExpressibleByArrayLiteral` or a `Sequence`?** `Sequence` iteration hands out elements by value (`next() -> Element?`), which requires copying, or consuming the container on every iteration. That doesn't work for noncopyable elements or a noncopyable container, so it conforms to the borrowing **`Iterable`** (SE-0516) instead. An array literal is built from a variadic (Copyable) array of elements, which would also force `Copyable`. Per the proposal, the type stays honest about ownership rather than pretending to be `Array`.

---

# Capstone: StayKit

**Solution:** [`Sources/StayKit/`](../Sources/StayKit) (5 files) and [`Tests/StayKitTests/`](../Tests/StayKitTests/StayKitTests.swift) (18 tests). The target is built with **warnings-as-errors** on Swift 6.4, and the only escape is a documented `@diagnose`.

## What was built, mapped to the spec

| # | Component | Implementation | From |
| --- | --- | --- | --- |
| C1 | Phantom IDs | `ListingID`, `HostID`, `ReservationID` = `Tagged<…, UUID>` | 14 |
| C2 | Value model + CoW | `Listing` value type. `AvailabilityCalendar` CoW, mutated in place with `calendars[id]?.block(nights)` | 01, 06 |
| C3 | Legacy JSON import | `ListingImporter` reuses `E19.ImportedListing` (polymorphic blocks, unknown types survive) | 19 |
| C4 | `some` / `any` | `makeRepository(_:) -> some E11.Repository<Listing>`; the service stores `any E11.Repository<Listing>` | 11, 12 |
| C5 | Search | `search(sortedBy:limit:) { E22.Destination(…) … }`: result-builder query, key-path `SortRule`s, lazy filter with early exit | 09, 10, 22 |
| C6 | Pricing | `QuoteEngine`: a `PricingRule` tree (weekly discount + cleaning fee, simplified), a `[7 of Double]` weekday table, and a `Span` average | 02, 29 |
| C7 | Clamped input | `E21.GuestRequest` (`@Clamped(1...16)`, `@Trimmed`) | 21 |
| C8 | N-ary validation | `E16.FormValidator(Rule<Range<Int>>, Rule<Int>, Rule<Decimal>)` in `hold` | 16 |
| C9 | Typed errors | `ListingError` / `PaymentError` / `BookingError`, `withRetry` keeps `PaymentError`, `@AddAsync` + `Result` bridge for the legacy client | 17, 18 |
| C10 | Ownership | `DraftReservation` → `ConfirmedReservation` → `CancelledReservation`; the `ReservationLock` moves through the states; `holdGroup` returns a `LockPool` (`UniqueArray`) | 24–27, 30 |
| C11 | Single-use token | `PaymentToken: ~Copyable` with `consuming func redeem()`; `Hashable` on 6.4 (synthesized) | 28 |
| C12 | Events | `Set<E15.AnyEventSink<BookingEvent>>`, deduplicated by identity | 08, 15 |
| C13 | Legacy bridge | `LegacyCatalogClient` with `@AddAsync`; `LegacyListingBridge` with `@diagnose(DeprecatedDeclaration, as: ignored, reason: …)` inside `#if compiler(>=6.4)` around the attribute | 20, 23 |
| C14 | 6.4 memberwise init | `Receipt` with `private var auditTrail = []` → `Receipt(reservationID:listingID:total:)` | SE-0502 |
| C15 | Sendable | every value type crossing a boundary is `Sendable`, Swift 6 language mode | Day 5 bridge |

**One change from the spec's API sketch:** I dropped `lockCapacity` from `BookingService.init`. The lock lives *inside* the reservation (that's what makes a dropped draft release its hold), so a pool owned by the service would hold locks the caller should own. The pool appears where it fits naturally: **group holds** (`holdGroup(_:) -> GroupHold`), where several locks are acquired all-or-nothing.

## The lifecycle in code

```swift
var service = BookingService(listings: listings)          // ~Copyable: one engine, no accidental forks
service.subscribe(BookingEventSink(analytics))

let results = service.search(sortedBy: [.init(\.rating, ascending: false), .init(\.nightlyPrice)]) {
    E22.Destination("Buenos Aires"); E22.Guests(2); E22.Amenity("wifi")
}
let quote = try service.quote(loft.id, nights: 3..<6, guests: .init(guests: 2, note: ""))   // throws(ListingError)
let draft = try service.hold(quote)                        // throws(BookingError); acquires the lock
let confirmed = try service.confirm(draft, paying: PaymentToken("tok_visa_42"))   // consumes draft AND token
let cancelled = service.cancel(confirmed, reason: "plans changed")                // consumes; releases the lock
```

The tests prove all of these:

| Test | What it proves |
| --- | --- |
| happy path | totals by hand (`330 = 3 × 100 + 30`); receipt trail; calendar blocked while confirmed, free after cancel; lock held while confirmed, released after; 3 events, with the duplicate subscriber deduplicated |
| declined payment | throws `.payment(.declined)`; the consumed draft was **dropped, so its lock was released by `deinit`** (`wasForced == true`); retrying with the same Copyable `Quote` works |
| double hold | `.lockUnavailable(id)` |
| dropping a draft | lock released at end of scope |
| validator | 30 nights + 5 guests in a 2-guest studio → `.invalidRequest(["nights", "guests"])` |
| pricing (parameterized) | 1, 3, 6, 7 and 14 nights, including the 10% weekly discount; the weekday surcharge comes from the `InlineArray` table |
| lazy search | `limit: 1` inspects **1** listing, not 4 |
| 6.4 suite | `PaymentToken` `==` without copying; the SE-0502 init; `holdGroup` all-or-nothing (macOS 27, skipped here) |

### Bugs and gotchas the capstone found

1. **Lazy filter re-evaluation.** `Array(matching.prefix(limit))` on a `LazyFilterCollection` ran the predicate **6 times to return 1 listing** (`startIndex`, `index(after:)` and `count` each re-filter). The fix is a single `for` loop with `break`.
2. **`.lazy` on an existential.** `listings.all().lazy` → *"member 'lazy' cannot be used on value of type 'any Collection<Listing>'"*. The fix is a generic helper `search(_ all: some Collection<Listing>, …)`, so implicit opening does the work.
3. **Partial consumption order.** `reservation.lock.release()` partially consumes `reservation`, so read `id`, `listingID` and `nights` *before*.
4. **Swift 6.3 differences:** `Receipt`'s memberwise init is `private` there (pre-SE-0502), so a 6.3-only explicit init is compiled in with `#if !compiler(>=6.4)`. Swift 6.3 also timed out type-checking a benchmark expression that 6.4 accepts.
5. **Testing noncopyables:** `#expect(service.isAvailable(…))` doesn't compile (a noncopyable receiver in the macro), and `#expect(throws:) { try service.confirm(draft, …) }` doesn't either (*"'draft' is borrowed and cannot be consumed"*: closures only borrow captures). Use local `Bool`s and `do`/`catch`.

## The 5 README design questions

1. **Why is `BookingService` noncopyable? What would go wrong with copies?** It owns mutable state: the catalog, calendars and subscribers. As a Copyable struct, `var other = service` would silently create a *second engine*: a booking on one copy wouldn't block the calendar of the other, so double bookings become possible. (With a shared class-backed pool, both copies would also release the same locks.) `~Copyable` makes "one engine" a compile-time fact. You pass it `inout` or borrow it, and `let copy = service; use(service)` is *"'service' used after consume"* (verified).
2. **`confirm` consumes the draft. On a `BookingError`, how does the caller get it back?** I chose **typed throws, and the caller doesn't get the draft back**. The draft is dropped, so its `deinit`-backed lock is released right away (no stuck holds), and the caller keeps the Copyable `Quote` to `hold` again. The alternative, Ex 26's `Transition.rejected(draft, reason:)`, keeps the hold during a retry, at the cost of an awkward non-throwing API. For payments, releasing the hold on failure is the safer default, because a declined card shouldn't block the listing for other guests.
3. **Why does the service store `any Repository` while the factory returns `some`?** The factory has one concrete implementation and wants to hide it while keeping static dispatch. The *service* must accept whatever the caller injects (in-memory in tests, a database adapter in production), chosen at runtime, so its stored property is an existential. Making `BookingService` generic over `R: Repository` would spread a generic parameter through every API that touches the service, for no measurable gain.
4. **Why does `QuoteEngine` average through `Span<Double>`, not `[Double]`?** The averaging function doesn't care where the doubles live. With a `Span` it can take the nightly array, an `InlineArray` window or a `UniqueArray` buffer without copying or retaining, with bounds checks, and with no generic specialization needed. Ex 29 measured why that matters in a hot loop.
5. **Which errors are typed, and why?** The **domain** errors (`ListingError`, `PaymentError`, `BookingError`) are typed: they're closed sets the app handles exhaustively, and generic helpers (`withRetry`) keep them. `ListingImporter` uses **untyped** `throws`: it wraps `JSONDecoder` (`DecodingError`), an open, foreign error domain that might gain cases. If StayKit were a *public, resilient* SDK, I'd reconsider making `BookingError` a public typed contract (Ex 18 memo), and probably expose an extensible error struct instead.

## 15-minute walkthrough (with this repo's numbers)

| Minute | Show | The one-liner | Likely follow-up → answer |
| --- | --- | --- | --- |
| 0–2 | The lifecycle code above | "Value types at the edges, unique ownership for anything that must happen exactly once." | "Why not classes plus a coordinator?" → identity and sharing aren't needed; ownership is |
| 2–4 | `AvailabilityCalendar` | "Value semantics by construction; CoW makes copies O(1) until a mutation." | "Is CoW thread-safe?" → a uniqueness check proves no other variable sees the buffer |
| 4–6 | `some`/`any` in the service | "`some` where the type is fixed, `any` where it's injected at runtime." | "Existential cost?" → 40 bytes, witness table, heap box beyond 3 words |
| 6–8 | Search DSL + `FormValidator` | "A builder for declarative input; packs for typed N-ary validation, no `Any`." | "Desugar the builder" → Ex 22 |
| 8–10 | Typed throws + the `@AddAsync` bridge | "Typed for closed internal domains; the macro migrates callbacks at compile time without erasing the error type." | "Adding an error case later?" → source-breaking, plan for it |
| 10–13 | Draft → Confirmed → Cancelled | "The compiler, not code review, guarantees one confirmation, one release, and one use of the payment token." | "Failed transition?" → the lock is released by `deinit`, the Quote is retried |
| 13–15 | Benchmark table | "Release build, medians and p90, and a fair baseline: 204× vs naive, but 15× vs a reused array. Most of the win is the allocation." | "When is InlineArray slower?" → large N copied by value |

## Definition of done

- [x] `swift build -c release` and `swift test` pass in the Swift 6 language mode with Swift 6.4.2. No warnings outside the documented `@diagnose` scopes. The package also passes on Swift 6.3.2.
- [x] Public types have doc comments explaining *why* they're a struct, enum, class or `~Copyable`.
- [x] The 5 design questions are answered above, and summarized in [swift-6.4-language.md](swift-6.4-language.md).
- [ ] Record the 15-minute walkthrough (that's for you).
- [ ] Rewrite 3 random components from scratch without notes in 45 minutes (that's for you, too).
