# Swift 6.4 Language Core: 30 Advanced Exercises + Capstone

## How to use this file

**Tutor mode rules (from the plan):** you write every line yourself. The agent explains, quizzes and reviews. It never writes the solution. That's why this file has **no solutions**. It gives a task, constraints, the tests you must write, interview drills and hints you can unfold.

For every exercise:

1. **Read first.** Open the linked resource (book chapter, WWDC session or SE proposal).
2. **Get quizzed.** Ask the Xcode agent: *"Quiz me on <concept> with 5 questions; don't give answers until I reply."*
3. **Predict, then build.** Write down what you expect the compiler and runtime to do *before* you write code.
4. **Prove it with tests.** Every exercise has a **Tests** list. Use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`).
5. **Drill.** Answer the **Interview drill** out loud in under 90 seconds per question, with no notes.
6. **Log it.** Add a short entry to `notes/swift-6.4-language.md`: one sentence for the concept, one gotcha and one code snippet.

**Difficulty scale.** All 30 are senior-level. The levels rank them against each other:

| Level | Meaning |
| --- | --- |
| L1 | Senior fundamentals: things you must explain flawlessly |
| L2 | Requires reasoning about compiler/runtime behavior |
| L3 | Design trade-offs plus non-obvious compiler rules |
| L4 | Ownership, performance or metaprogramming; few engineers have practiced it |
| L5 | Cutting-edge (Swift 6.2–6.4); combines the hardest rules |

**Shared domain.** Every exercise uses one Airbnb-style booking domain (listings, hosts, reservations, pricing), so the pieces build up toward the capstone.

### Package layout (from the plan)

```
swift-mastery/
├── Package.swift                 // swift-tools-version: 6.2+ (6.4 for Ex 27–30)
├── Sources/
│   ├── Language/                 // Ex 01–22, one file per exercise: E01_ValueSemantics.swift …
│   ├── LanguageMacros/           // Ex 23 macro implementation (.macro target, depends on swift-syntax)
│   ├── LanguageMacrosClient/     // Ex 23 macro declarations
│   ├── Payments/ , Pricing/      // Ex 05 module-selector modules
│   ├── Ownership/                // Ex 24–30, noncopyable exercises + benchmark
│   └── StayKit/                  // Capstone
├── Benchmarks/                   // Ex 29–30 (ordo-one/package-benchmark or ContinuousClock harness)
└── Tests/
    ├── LanguageTests/
    ├── OwnershipTests/
    └── StayKitTests/
```

> Swift 6.4 uses **Swift Build** as the default build system, so `swift build` and `swift test` already use it. If the build differs between Xcode and the CLI, record the difference in your notes. That's a good platform-engineering talking point.

### Coverage map

| Topic | Exercises |
| --- | --- |
| Types and semantics | 01 value vs reference · 02 pattern matching · 03 optionals · 04 extensions & dispatch · 05 module selectors · 06 copy-on-write |
| Functions and closures | 07 `inout` & exclusivity · 08 escaping closures & capture lists · 09 key paths · 10 lazy sequences |
| Protocols and generics | 11 associated & primary associated types · 12 `some` vs `any` · 13 generic constraints · 14 conditional conformance · 15 type erasure · 16 parameter packs |
| Errors and data | 17 `Result` · 18 typed throws · 19 advanced `Codable` |
| Advanced language | 20 `@diagnose` · 21 property wrappers · 22 result builders · 23 macros |
| Ownership and performance | 24 `~Copyable` · 25 `borrowing` / `consuming` · 26 typestate · 27 noncopyable generics · 28 noncopyable `Equatable`/`Hashable` · 29 `InlineArray` + `Span` · 30 `UniqueArray` / `UniqueBox` |

| New in Swift 6.3/6.4 | Where | Proposal |
| --- | --- | --- |
| `any P?` / `some P?` shorthand | Ex 12 | [SE-0521](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0521-improved-optional-opaque-and-any.md) (6.4) |
| Module selectors `Module::Name` | Ex 05 | [SE-0491](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0491-module-selectors.md) (implemented in **6.3**; the 6.4 coverage lists it as well) |
| `@diagnose` | Ex 20 | [SE-0522](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0522-source-warning-control.md) (6.4) |
| Noncopyable `Equatable` / `Comparable` / `Hashable` | Ex 28 | [SE-0499](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0499-support-non-copyable-simple-protocols.md) (6.4) |
| `UniqueBox` | Ex 30 | [SE-0517](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0517-uniquebox.md) (6.4) |
| `UniqueArray` / `RigidArray` | Ex 30 | [SE-0527](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0527-rigidarray-uniquearray.md) (6.4) |
| Borrow / mutate accessors | Ex 30 | [SE-0507](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0507-borrow-accessors.md) (6.4) |
| `Iterable` (borrowing iteration) | Ex 30 (stretch) | [SE-0516](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0516-borrowing-sequence.md) (6.4) |
| `private` defaulted properties excluded from memberwise init | Capstone | [SE-0502](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0502-exclude-private-from-memberwise-init.md) (6.4) |

---

# Tier 1: Types and semantics

## 01. Value vs reference semantics (L1)

**Concept:** what "value semantics" actually means. It's a property of the *type's behavior*, not of the `struct` keyword.

**Why interviewers ask:** "Is a struct always a value type?" separates people who memorized the answer from people who understand it.

**Task.** You inherit this model:

```swift
final class PhotoGallery {
    var urls: [URL] = []
}

struct Listing {
    var title: String
    var nightlyPrice: Decimal
    var gallery: PhotoGallery
}
```

1. Write tests that **prove** `Listing` doesn't have value semantics: copy it, mutate the copy's gallery, then observe the original.
2. Redesign `Listing` so that it has full value semantics *without* changing its public API (`listing.gallery.urls.append(...)` must still compile). Don't use copy-on-write yet (that's Ex 06).
3. Add a `final class Host` that's correctly a reference type (identity matters: two hosts with the same name are different people). Give `Listing` a `host` property and explain why sharing it is *correct* here.

**Constraints:** no `NSCopying`. No custom `init` that deep-copies (the type must be a value type by construction).

**Tests**
- `copyDoesNotShareGallery`: mutating a copy leaves the original unchanged.
- `hostIsShared`: two listings share the same host (check with `===`).
- `letListingIsImmutable`: write it as a comment, because code that fails to compile can't be a test. Explain why `let l = Listing(...); l.gallery.urls.append(x)` fails for your struct but would compile for the original class-backed design.

**Interview drill**
- Define value semantics without using the words "struct" or "copy".
- Where do structs live in memory? (Watch out: the stack is not guaranteed. Name 3 cases where a struct ends up on the heap.)
- When would you deliberately choose a class in a Swift 6 codebase?

<details><summary>Hints</summary>

- "Value semantics" = mutating one variable can never be observed through another variable.
- A struct is only as value-like as its stored properties.
- Heap cases: captured by an escaping closure, stored in an existential larger than the inline buffer, a property of a class, `indirect` enum payloads.
</details>

**Read first:** Swift book, [Structures and Classes](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/classesandstructures/). *Advanced Swift*, ch. "Structs and Classes".

---

## 02. Enums with associated values and pattern matching (L1)

**Concept:** pattern matching as a language feature: nested patterns, `where` guards, tuple patterns, `if case`/`guard case`, `for case` and custom `~=`.

**Task.** Model pricing rules as a recursive enum:

```swift
indirect enum PricingRule: Equatable {
    case nightly(Decimal)
    case cleaningFee(Decimal)
    case percentOff(Int, PricingRule)
    case combined(PricingRule, PricingRule)
    case ifStayAtLeast(nights: Int, then: PricingRule, else: PricingRule)
}

extension PricingRule {
    func total(nights: Int) -> Decimal { fatalError("TODO") }
    func simplified() -> PricingRule { fatalError("TODO") }
}
```

1. `total(nights:)`: evaluate recursively.
2. `simplified()`: use **nested patterns** to rewrite these cases:
   - `.percentOff(0, r)` → `r`
   - `.combined(.nightly(0), r)` and `.combined(r, .nightly(0))` → `r`
   - `.percentOff(a, .percentOff(b, r))` → *think:* is this `a + b`? (It isn't. Write the correct rule.)
   - `.ifStayAtLeast(nights: n, then: a, else: b)` where `a == b` → `a`
3. Write a custom pattern operator so this compiles: `switch nights { case StayLength.weekly: … case StayLength.monthly: … }`, where `StayLength` is your own type (not a `Range`).
4. Use `for case .cleaningFee(let fee) in rules` to sum all cleaning fees in a flat `[PricingRule]`.

**Tests**
- Parameterized `@Test(arguments:)` over 6+ rule trees, checking `total`.
- `simplified()` is idempotent: `r.simplified().simplified() == r.simplified()`.
- `simplified()` preserves meaning: `r.total(n) == r.simplified().total(n)` for n in 1...40.

**Interview drill**
- What does `indirect` change in memory layout? Why can't a non-indirect enum contain itself?
- Why does the compiler force exhaustive switches, and what does `@unknown default` protect you from (library evolution / non-frozen enums)?
- How does `~=` participate in `switch`?

<details><summary>Hints</summary>

- `static func ~= (pattern: StayLength, value: Int) -> Bool`
- For the simplifier, simplify children first (bottom-up), then match the parent.
</details>

**Read first:** Swift book, [Enumerations](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/enumerations/) and [Patterns](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/patterns/).

---

## 03. Optionals from first principles (L1)

**Concept:** `Optional` is just a generic enum plus a lot of compiler sugar. Rebuild it to understand the sugar.

**Task.** Implement `enum Maybe<Wrapped>` with no help from `Optional`:

```swift
enum Maybe<Wrapped> {
    case none
    case some(Wrapped)
}
```

1. `map`, `flatMap`, and `unwrapped(or:)`.
2. A `??`-like operator `|?` with `@autoclosure` so the right side is **only evaluated when needed**.
3. `ExpressibleByNilLiteral` so `let m: Maybe<Int> = nil` compiles.
4. Conditional `Equatable`.
5. Then switch to the real `Optional` and explain the double-optional trap:
   ```swift
   let overrides: [String: Int?] = ["price": nil]
   let v = overrides["price"]   // what is the type? what is the value?
   ```
   Write code that tells apart "key missing" from "key present with nil".

**Tests**
- `rhsNotEvaluatedWhenSome`: a counter proves the autoclosure isn't called.
- `flatMapFlattens`: `Maybe<Maybe<Int>>` collapses.
- `doubleOptional`: distinguishes `.none` from `.some(.none)`.

**Interview drill**
- What does optional chaining `a?.b?.c()` desugar to?
- `if let x`, `guard let x`, and `if let x = x`: what does SE-0345 shorthand change?
- Why is `@autoclosure` dangerous in APIs (hidden laziness / hidden side effects)?

**Read first:** Swift book, [The Basics → Optionals](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/thebasics/#Optionals) and [Optional Chaining](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/optionalchaining/).

---

## 04. Extensions and method dispatch (L2)

**Concept:** static dispatch vs witness-table dispatch vs vtable dispatch, and the classic protocol-extension trap.

**Task.**

```swift
protocol Describable {
    func summary() -> String              // requirement
}

extension Describable {
    func summary() -> String { "generic summary" }
    func badge() -> String { "generic badge" }   // NOT a requirement
}

struct Listing: Describable {
    func summary() -> String { "listing summary" }
    func badge() -> String { "listing badge" }
}

class BaseCard: Describable {}                    // uses the default summary()
class PremiumCard: BaseCard {
    func summary() -> String { "premium summary" } // what happens here?
}
```

1. **Predict first**, then test, the result of `summary()` and `badge()` when called through: the concrete type, a generic `<T: Describable>`, `any Describable`, and for `PremiumCard` also through `BaseCard`.
2. Explain the `PremiumCard` result. Then fix it in two different ways and explain the trade-offs.
3. Add `final` and `private` to members and explain how each enables devirtualization.

**Tests:** one `@Test(arguments:)` table: `(callSite, expected)` with ≥ 10 rows, all predicted before running.

**Interview drill**
- What's a protocol witness table? What's a vtable? Which one does `any Describable` use?
- Why can't you override a method declared in an extension of a class (without `@objc dynamic`)?
- How does whole-module optimization change dispatch?

<details><summary>Hints</summary>

- The witness table for `BaseCard: Describable` is built when `BaseCard` conforms. It points at the extension's default.
- Fixes: implement `summary()` in `BaseCard` so `PremiumCard` can `override`, or rethink the hierarchy.
</details>

**Read first:** Swift book, [Extensions](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/extensions/) and [Protocols → Protocol Extensions](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/#Protocol-Extensions). WWDC22 *Design protocol interfaces in Swift*.

---

## 05. Module selectors `Module::Name` (L2, Swift 6.3+)

**Concept:** name lookup across modules, and how module selectors disambiguate it.

**Task.** In your package, create two library targets that collide on purpose:

```swift
// Sources/Payments/Money.swift
public struct Money { public var cents: Int; public var currency: String }
extension String { public var slug: String { "pay-" + lowercased() } }

// Sources/Pricing/Money.swift
public struct Money { public var amount: Decimal }
extension String { public var slug: String { "price-" + lowercased() } }
```

In a third target (`Language`) that imports both:

1. Declare a function that takes a `Payments::Money` and returns a `Pricing::Money`.
2. Call the `slug` extension from **each** module on the same string (a module selector on a member: `name.Payments::slug`).
3. Shadowing: inside `struct Checkout { struct Money {} }`, refer to the **top-level** `Money` of your own module with `Language::Money`.
4. Reproduce the old "module and type share a name" problem: add a target `Listing` with `public struct Listing`, then write why `Listing.Listing` was broken before selectors and how `Listing::Listing` fixes it.
5. Try `struct Payments::Refund {}` and record the compiler error. Why are selectors forbidden on new declarations?

**Tests:** conversions produce the right values. Each `slug` resolves to its own module's implementation.

**Interview drill**
- Qualified vs unqualified lookup: which one does `Module::` affect, and how?
- Why is the selector useful for **macro authors** and generated code (they can't control what's in scope at the expansion site)?
- How does this help a migration agent that rewrites code across a large monorepo?

**Read first:** [SE-0491](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0491-module-selectors.md).

---

## 06. Copy-on-write by hand (L3)

**Concept:** implementing CoW with `isKnownUniquelyReferenced`.

**Task.** Build `struct AvailabilityCalendar` (365 days × availability + price) with value semantics and CoW:

```swift
struct AvailabilityCalendar {
    private final class Storage {
        var days: [DayInfo]
        init(days: [DayInfo]) { self.days = days }
    }
    private var storage: Storage

    // Test hook: identity of the buffer
    var _storageID: ObjectIdentifier { ObjectIdentifier(storage) }

    subscript(day: Int) -> DayInfo { get { fatalError() } set { fatalError() } }
    mutating func block(_ range: Range<Int>) { fatalError() }
}
```

1. Copying a calendar is O(1) and shares storage until one side mutates.
2. Mutation on a uniquely referenced buffer **never** reallocates.
3. Make the subscript work with in-place mutation (`calendar[3].price += 10`) without a temporary copy of the whole buffer. Use `_modify` or the 6.4 `mutate` accessor (SE-0507) and explain the difference.
4. Find and fix the CoW-defeating bug: storing `self` in a closure or iterating while mutating (`for i in cal.indices { cal[i] = … }` while another reference is alive).

**Tests**
- `copySharesStorage` / `mutationUnshares` / `uniqueMutationDoesNotReallocate` (compare `_storageID`s).
- A rough performance test: 100k mutations on a unique calendar finish in under X ms (set X after your first measurement and justify it).

**Interview drill**
- Is CoW automatic for every struct? (No. Explain which stdlib types implement it.)
- Why must `Storage` be a `final class`? What breaks with `isKnownUniquelyReferenced` on `weak`/`unowned`?
- Is CoW thread-safe? What exactly does the uniqueness check guarantee?

**Read first:** *Advanced Swift*, ch. "Structs and Classes → Copy-on-Write". WWDC25 *Improve memory usage and performance with Swift*.

---

# Tier 2: Functions and closures

## 07. `inout` and the Law of Exclusivity (L2)

**Concept:** `inout` is copy-in/copy-out (semantically), plus exclusive access enforced at compile time *and* at runtime.

**Task.**

1. `func applyDiscount(_ price: inout Decimal, percent: Int)`.
2. Give `Listing` a `nightlyPrice` with a `didSet` that increments a counter. Pass `&listing.nightlyPrice` to a function that mutates the value **3 times**. How many times does `didSet` fire? Prove it with a test and explain why.
3. Write code that makes the compiler report **overlapping accesses**:
   - `func transfer(_ a: inout Int, _ b: inout Int)` called as `transfer(&x, &x)`
   - `swap(&nights[0], &nights[1])`. Why is this an error but `nights.swapAt(0, 1)` is fine?
4. Write code that compiles but **traps at runtime** ("Simultaneous accesses to …"): a class property mutated inside a closure that's called while the same property is passed `inout`.
5. Mutating a struct's two different stored properties at once is allowed for a local struct. When does that stop being allowed (global variable, class property)?

**Tests**
- `didSetFiresOnce`
- Use a Swift Testing **exit test** to prove the runtime trap from step 4:
  ```swift
  @Test func exclusivityViolationTraps() async {
      await #expect(processExitsWith: .failure) {
          // trigger the violation here
      }
  }
  ```

**Interview drill**
- Why does Swift enforce exclusivity at all (optimizer, memory safety, CoW)?
- `inout` vs `UnsafeMutablePointer` vs a class reference: when would you use each?

**Read first:** Swift book, [Memory Safety](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/memorysafety/) and [Functions → In-Out Parameters](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/functions/#In-Out-Parameters).

---

## 08. Escaping closures and capture lists (L2)

**Concept:** what a closure captures, when, and who owns whom.

**Task.**

```swift
final class ListingDetailModel {
    var title = ""
    var onChange: (() -> Void)?
    let loader: ImageLoader
    init(loader: ImageLoader) { self.loader = loader }
    func start() { /* register callbacks that reference self */ }
    deinit { DeinitTracker.record("ListingDetailModel") }
}

final class ImageLoader {
    private var completions: [(Data) -> Void] = []
    func load(_ url: URL, completion: @escaping (Data) -> Void) { completions.append(completion) }
    func finishAll(with data: Data) { completions.forEach { $0(data) }; completions.removeAll() }
}
```

1. Create a retain cycle inside `start()`. Prove it with a test.
2. Fix it three ways: `[weak self]`, `[unowned self]`, and restructuring so self isn't captured (capture only what you need: `[loader, title]`). Explain when `unowned` would crash.
3. Capture semantics: show that a closure captures a **variable** by reference (sees later mutations), while a capture-list entry `[snapshot = value]` captures the **value** at creation time.
4. Use `withoutActuallyEscaping` to pass a non-escaping closure to an API that formally requires `@escaping` (e.g. a lazy `filter`), and explain the contract you must honor.

**Tests**
- `modelIsDeallocated`: `weak var weakModel` is `nil` after the scope ends.
- `captureByReference` vs `captureListSnapshot`.

**Interview drill**
- Why are closure parameters non-escaping by default?
- `[weak self]` + `guard let self` vs `self?.` chains: what's different in the semantics (atomicity of a multi-step operation)?
- In Swift 6, what does `@Sendable` add to an escaping closure's capture rules?

**Read first:** Swift book, [Closures](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/closures/) and [Automatic Reference Counting → Strong Reference Cycles for Closures](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/#Strong-Reference-Cycles-for-Closures).

---

## 09. Key paths (L2)

**Concept:** key paths as first-class, composable, type-safe property references.

**Task.**

1. `extension Sequence { func sorted<V: Comparable>(by kp: KeyPath<Element, V>, ascending: Bool = true) -> [Element] }`
2. A multi-key sort descriptor that **erases** the value type:
   ```swift
   struct SortRule<Root> {
       init<V: Comparable>(_ keyPath: KeyPath<Root, V>, ascending: Bool = true)
       // store a comparator closure, not the key path
   }
   extension Sequence {
       func sorted(by rules: [SortRule<Element>]) -> [Element]
   }
   // usage: listings.sorted(by: [.init(\.rating, ascending: false), .init(\.nightlyPrice)])
   ```
3. A generic updater `func updating<V>(_ root: Root, _ kp: WritableKeyPath<Root, V>, to value: V) -> Root`.
4. Key path composition: build `\Listing.host.name` from `\Listing.host` and `\Host.name` using `appending(path:)`.
5. Key paths as functions: `listings.map(\.title)` (SE-0249). Explain what the compiler synthesizes.

**Tests:** multi-key sort with ties. `updating` doesn't mutate the original. The appended key path reads the correct value.

**Interview drill**
- Name the `KeyPath` class hierarchy (`AnyKeyPath` → `PartialKeyPath` → `KeyPath` → `WritableKeyPath` → `ReferenceWritableKeyPath`). Why is `ReferenceWritableKeyPath` separate?
- Key paths and `Sendable` in Swift 6: when is a key path literal `Sendable`?
- Where do key paths show up in SwiftUI / SwiftData / `@Observable`?

**Read first:** [SE-0161](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0161-key-paths.md), [SE-0249](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0249-key-path-literal-function-expressions.md). *Advanced Swift*, ch. "Functions → Key Paths".

---

## 10. Custom sequences and lazy evaluation (L3)

**Concept:** `Sequence`/`IteratorProtocol` plus the laziness model of `LazySequenceProtocol`.

**Task.**

1. `struct StayNights: Sequence` that yields each night's `Date` from check-in to check-out (calendar-aware, DST-safe).
2. `struct PriceSeries: Sequence`: an **infinite** sequence of nightly prices with a seasonal multiplier.
3. Pipeline: `PriceSeries().lazy.filter { … }.map { … }.prefix(30)`. Use counters to prove:
   - the eager version would never terminate on an infinite input
   - the lazy version evaluates `filter`/`map` **only** as many times as needed
   - iterating a lazy pipeline **twice** re-runs the closures (the "lazy isn't cached" trap)
4. Implement your own lazy adapter `chunked(by:)` that conforms to `LazySequenceProtocol`, so `.lazy.chunked(by: 7)` stays lazy.
5. Explain why `first(where:)` on a lazy filter isn't faster than on an eager one, while `.lazy.map(...).first` is.

**Tests:** closure invocation counts (exact numbers). Correct DST handling in `StayNights` around a known DST date.

**Interview drill**
- `Sequence` vs `Collection`: what guarantees does `Collection` add (multi-pass, indices, O(1) `count`?)?
- When does `lazy` hurt performance?
- `some Sequence<Date>` as a return type vs `AnySequence<Date>`: which would you pick and why? (This links to Ex 12 and 15.)

**Read first:** *Advanced Swift*, ch. "Built-In Collections" and "Collection Protocols". Swift docs for `LazySequenceProtocol`.

---

# Tier 3: Protocols and generics

## 11. Associated types and primary associated types (L2)

**Concept:** protocols with associated types (PATs), primary associated types (SE-0346) and protocol design.

**Task.**

```swift
protocol Repository<Entity> {
    associatedtype Entity: Identifiable
    associatedtype Entities: Collection = [Entity] where Entities.Element == Entity

    func all() -> Entities
    func find(_ id: Entity.ID) -> Entity?
    mutating func upsert(_ entity: Entity)
}
```

1. `struct InMemoryRepository<E: Identifiable>: Repository`
2. `struct SortedRepository<E: Identifiable & Comparable>: Repository` with `Entities = [E]` kept sorted (or a custom collection).
3. `func makeListingRepository() -> some Repository<Listing>`. Then show what a caller **can** and **cannot** know about `Entities`.
4. Add a protocol extension `extension Repository where Entity: Hashable { func duplicates() -> … }`.
5. Design question: should `Entity.ID` be a separate primary associated type? Write your argument (one paragraph) in the file's doc comment.

**Tests:** both repositories behave the same against one shared **parameterized** test suite (generic test helper over `some Repository<Listing>`).

**Interview drill**
- Why couldn't you write `let r: Repository` before Swift 5.7?
- How do you choose which associated type is "primary"? (The one callers constrain most often, like `Element` in `Collection<Element>`.)
- Associated type vs generic parameter on the protocol (which Swift doesn't have): why does Swift choose associated types?

**Read first:** Swift book, [Generics → Associated Types](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/generics/#Associated-Types). [SE-0346](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0346-light-weight-same-type-syntax.md). WWDC22 *Design protocol interfaces in Swift*.

---

## 12. `some` vs `any` (L3, includes the Swift 6.4 shorthand)

**Concept:** opaque types (fixed hidden type, static dispatch) vs existentials (boxed, dynamic type), implicit opening, and the cost model.

**Task.**

```swift
protocol PricingStrategy {
    func price(nights: Int) -> Decimal
}
struct StandardPricing: PricingStrategy { … }
struct WeeklyDiscount: PricingStrategy { … }
struct SurgePricing: PricingStrategy { … }
```

1. Write `func strategy(for season: Season) -> some PricingStrategy` that returns different types per branch. Record the error, then fix it **two** ways (switch to `any`; or keep `some` with a single wrapper type) and compare them.
2. A heterogeneous `[any PricingStrategy]`: compute the cheapest quote.
3. **Implicit opening (SE-0352):** pass an `any PricingStrategy` into `func audit<S: PricingStrategy>(_ s: S) -> String` that prints `S.self`. Explain what changed in Swift 5.7.
4. Lost information: with `any Repository<Listing>` from Ex 11, which members are still callable, and what does `all()` return? (Covariant erasure to `any Collection<Listing>`.)
5. **Swift 6.4 shorthand (SE-0521):** rewrite every `(any PricingStrategy)?` and `(some PricingStrategy)?` in your code as `any PricingStrategy?` / `some PricingStrategy?`. Then try `any PricingStrategy & Sendable?` and explain why it's still rejected while `any (PricingStrategy & Sendable)?` is accepted.
6. Measure: `MemoryLayout<any PricingStrategy>.size` vs `MemoryLayout<StandardPricing>.size` vs `MemoryLayout<any PricingStrategy & AnyObject>.size`, plus an optional existential. Explain each number.

**Tests**
- `#expect(MemoryLayout<any PricingStrategy>.size == 40)` (64-bit). Explain the 5 words: 3-word inline buffer + metadata + witness table.
- A `some` parameter (`func quote(_ s: some PricingStrategy)`) and the generic version are interchangeable at call sites.

**Interview drill**
- "Use `some` by default, `any` when you need heterogeneity or a stored dynamic type." Defend or refine that rule.
- What happens when a value doesn't fit in the existential's inline buffer?
- `some` in parameter position vs in return position: who chooses the concrete type in each case?

**Read first:** Swift book, [Opaque and Boxed Protocol Types](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/). WWDC22 [Embrace Swift generics](https://developer.apple.com/videos/play/wwdc2022/110352/). [SE-0352](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0352-implicit-open-existentials.md), [SE-0521](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0521-improved-optional-opaque-and-any.md).

---

## 13. Generic constraints and constrained extensions (L3)

**Concept:** `where` clauses, same-type requirements, overload ranking, and **why constraints resolve statically**.

**Task.**

1. `extension Collection where Element: AdditiveArithmetic { func sum() -> Element }`
2. `extension Sequence where Element == Listing { func averagePrice() -> Decimal }`
3. `func mergeUnique<A: Sequence, B: Sequence>(_ a: A, _ b: B) -> [A.Element] where A.Element == B.Element, A.Element: Hashable`
4. Two overloads of `median()`:
   - `extension Collection where Element: Comparable` (generic, O(n log n))
   - `extension RandomAccessCollection where Element: Comparable` (index arithmetic)
   Add a `static var calls` counter to see which overload runs.
5. **The trap:** call `median()` from inside `func report<C: Collection>(_ c: C) where C.Element: Comparable` and pass an `Array`. Which overload runs? Prove it, then explain why. Fix it by making `median()` a **protocol requirement with a default implementation** (a customization point), and show the fix works.

**Tests:** direct call on `Array` → RAC overload. Call through `report` → Collection overload (before the fix) and RAC overload (after).

**Interview drill**
- Overload resolution happens at compile time. Customization points need protocol requirements. Explain this with the stdlib's `count` on `Collection` vs `Sequence.underestimatedCount`.
- What does "specialization" mean for generics, and when can the optimizer *not* specialize (across module boundaries without `@inlinable`)?

**Read first:** Swift book, [Generics → Generic Where Clauses / Extensions with a Generic Where Clause](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/generics/#Generic-Where-Clauses). *Advanced Swift*, ch. "Generics".

---

## 14. Conditional conformance and phantom types (L3)

**Concept:** conforming a generic type to a protocol only when its parameters do.

**Task.** Build a type-safe identifier:

```swift
struct Tagged<Tag, RawValue> {
    let rawValue: RawValue
}

typealias ListingID = Tagged<Listing, UUID>
typealias HostID    = Tagged<Host, UUID>
```

1. Conditional conformances: `Equatable`, `Hashable`, `Comparable`, `Sendable`, `Codable` (encode as the **bare** raw value, not `{"rawValue": …}`), `CustomStringConvertible`, `ExpressibleByStringLiteral` / `ExpressibleByIntegerLiteral` when `RawValue` is.
2. Prove at compile time that a `ListingID` can't be passed where a `HostID` is expected (write it as a commented-out line with the compiler error).
3. `Tag` is never stored. Explain why `Tagged<Listing, UUID>` can be `Sendable` even when `Listing` is not, and how you'd write that.
4. Bonus: conditional conformance on a type you don't own: `extension Optional: PricingStrategy where Wrapped: PricingStrategy` (nil → price 0). Is that a good idea? Argue it.

**Tests:** `Set<ListingID>` works. JSON round-trip matches `"5F1B…"` (a bare string). Literal init works for `Tagged<Listing, Int>`.

**Interview drill**
- What's a phantom type, and what does it cost at runtime? (Nothing. Check with `MemoryLayout`.)
- Why can't a type conform to the same protocol twice with different conditions?
- Dynamic casts and conditional conformance: is `(tagged as Any) as? any Hashable` resolved at runtime?

**Read first:** [SE-0143](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0143-conditional-conformances.md). Swift book, [Protocols → Conditionally Conforming to a Protocol](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/#Conditionally-Conforming-to-a-Protocol).

---

## 15. Type erasure (L3)

**Concept:** manual type erasure, and when `any P<T>` is (and isn't) enough in modern Swift.

**Task.**

```swift
protocol EventSink<Event> {
    associatedtype Event
    func send(_ event: Event)
}
```

1. Write `struct AnyEventSink<Event>: EventSink` **two ways**:
   - closure-based (store `send` as `(Event) -> Void`)
   - class-box based (`private class _Box<Event>` base with a `final class _ConcreteBox<S: EventSink>: _Box<S.Event>` subclass)
2. Compare both with `any EventSink<BookingEvent>`: memory, dispatch and what each can conform to.
3. Show **why** manual erasure is still needed: make `AnyEventSink` conform to `Hashable` (by sink identity) and put sinks in a `Set`. Try the same with `any EventSink<BookingEvent>` and record the error. Existentials don't conform to protocols (except special cases like `any Error`).
4. Erase a sink that's a **struct with mutable state**. Which erasure strategy preserves the value semantics you expect?

**Tests:** all three dispatch to the same underlying sink. Set membership works. The struct-state test documents the semantics you chose.

**Interview drill**
- How does `AnyHashable` / `AnySequence` work internally?
- Why is `any Error` allowed where `some Error` / `E: Error` is expected ("self-conformance")?
- In a public SDK, would you expose `AnyEventSink` or `any EventSink<E>`? (ABI, evolution, conformances.)

**Read first:** *Advanced Swift*, ch. "Protocols → Type Erasers". WWDC22 *Design protocol interfaces in Swift*.

---

## 16. Parameter packs / variadic generics (L4)

**Concept:** `each T`, `repeat`, pack expansion, tuples of packs, and pack iteration (SE-0393, SE-0398, SE-0399, SE-0408).

**Task.**

1. Replace an overload family `zip2/zip3/zip4` with **one** function:
   ```swift
   func zipAll<each S: Sequence>(_ s: repeat each S) -> [(repeat (each S).Element)]
   ```
   (Hint: you need an iterator per sequence. Decide how to stop at the shortest.)
2. A typed form validator for any number of fields:
   ```swift
   struct Rule<Value> { let name: String; let isValid: (Value) -> Bool }

   struct FormValidator<each Field> {
       let rules: (repeat Rule<each Field>)
       init(_ rules: repeat Rule<each Field>)
       func failures(_ values: repeat each Field) -> [String]
   }

   let v = FormValidator(
       Rule<String>(name: "title") { !$0.isEmpty },
       Rule<Int>(name: "guests") { (1...16).contains($0) },
       Rule<Decimal>(name: "price") { $0 > 0 }
   )
   v.failures("", 20, 99)   // ["title", "guests"]
   ```
3. `func allPresent<each T>(_ v: repeat (each T)?) -> (repeat each T)?`: returns the unwrapped tuple only if **every** value is non-nil. (This is a typed `if let a, let b, let c` for any arity.)
4. Use **pack iteration** (`for x in repeat each pack`) somewhere and explain its limits.

**Constraints:** no `Any`, no `as?`. Everything must be statically typed.

**Tests:** arities 1, 2, 3 and 5 for every function. `failures` keeps the order of the fields. `allPresent` returns `nil` when any value is missing.

**Interview drill**
- What problem do packs solve that `[Any]` and overload families don't?
- What's the difference between a **type pack** and a **value pack**? What does `repeat` expand?
- Where do packs appear in the frameworks you use (SwiftUI `ViewBuilder.buildBlock`, `#Predicate`)?

<details><summary>Hints</summary>

- Inside `failures`: `repeat check(each rules, each values)` with a local generic helper that appends to an outer `var`.
- `allPresent`: you can't early-return from inside a `repeat` expression. Use a helper that throws or returns `T?`, and think about how to fold the results.
</details>

**Read first:** [SE-0393](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0393-parameter-packs.md), [SE-0398](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0398-variadic-types.md), [SE-0408](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0408-pack-iteration.md). WWDC23 *Generalize APIs with parameter packs*.

---

# Tier 4: Errors and data

## 17. `Result` as a value (L2)

**Concept:** `Result<Success, Failure>` as a first-class value: transformation, aggregation and bridging between callback, throwing and async code.

**Task.**

1. A legacy API: `func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void)`.
2. Implement on `Result`:
   - `zip(_ other:)` → `Result<(A, B), Failure>`
   - `static func collect(_ results: [Result<S, F>]) -> Result<[S], F>` (fail fast on the first failure)
   - `func recover(_ f: (Failure) -> Success) -> Result<Success, Never>`
3. Bridge to async **without losing the error type**: `func fetchListing(id:) async throws(ListingError) -> Listing` using a checked continuation that resumes with a `Result`, then `.get()`.
4. Show `Result(catching:)` preserving a typed error from a `throws(ListingError)` closure.
5. Write a short paragraph: when is `Result` still better than `throws` in Swift 6 (storing outcomes, batch processing, memoization)?

**Tests:** `collect` fails fast (count how many closures run). `recover` gives `Result<_, Never>`, and `get()` needs no `try`. The async bridge preserves `ListingError` (exhaustive `catch` with no fallback).

**Interview drill**
- `Result<T, any Error>` vs `throws`: which composes better and why?
- Why does `Result<_, Never>.get()` not need `try`?

**Read first:** [SE-0235](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0235-add-result.md). Swift book, [Error Handling](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/errorhandling/).

---

## 18. Typed throws (L3)

**Concept:** `throws(E)`, error-type inference, generic error propagation and the API-design rules from SE-0413.

**Task.**

```swift
enum ListingError: Error, Equatable {
    case notFound(ListingID)
    case invalidPrice(Decimal)
    case unavailable(Range<Date>)
}
enum PaymentError: Error { case declined, fraudSuspected }
enum BookingError: Error {
    case listing(ListingError)
    case payment(PaymentError)
}
```

1. `func validate(_ l: Listing) throws(ListingError)`, then call it inside `do throws(ListingError) { … } catch { … }`. Show the `catch` is exhaustive over `ListingError` **with no `default`**.
2. `func book(...) throws(BookingError)` composes listing and payment calls. Map the inner errors **explicitly**, and record what happens if you forget (the inferred type).
3. A generic retry that **preserves** the caller's error type:
   ```swift
   func withRetry<T, E: Error>(attempts: Int, _ op: () throws(E) -> T) throws(E) -> T
   ```
   Call it with a non-throwing closure and show that `try` isn't required (`E == Never`).
4. Replace a `rethrows` function with a typed-throws generic and explain why typed throws subsumes `rethrows`.
5. **Design memo** (≤ 10 lines): SE-0413 recommends untyped `throws` for most public APIs. When is typed throws the right call (closed error domains, embedded, generic propagation, performance), and why can it hurt library evolution?

**Tests:** parameterized over every `ListingError` case. `withRetry` returns after N attempts and rethrows the **same** error type (`#expect(throws: ListingError.self)`).

**Interview drill**
- What are `throws`, `throws(any Error)` and `throws(Never)` equivalent to?
- How does typed throws interact with `async let` / `TaskGroup` (where the error type gets erased)?
- How do you evolve a public `throws(ListingError)` API when you need a new failure mode?

**Read first:** [SE-0413](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0413-typed-throws.md). Swift book, [Error Handling → Specifying the Error Type](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/errorhandling/#Specifying-the-Error-Type).

---

## 19. Advanced `Codable` (L3)

**Concept:** hand-written `init(from:)`/`encode(to:)` with nested and keyed containers, polymorphism and resilience.

**Task.** Decode this API payload into clean domain types:

```json
{
  "listing_id": "5F1B6C1E-…",
  "title": "Loft in Palermo",
  "location": { "lat": -34.58, "lng": -58.42 },
  "price": { "amount": "120.50", "currency": "USD" },
  "available_from": "2026-12-01",
  "updated_at": "2026-11-06T10:15:00Z",
  "blocks": [
    { "type": "text", "body": "Sunny loft" },
    { "type": "photo", "url": "https://…", "caption": null },
    { "type": "amenities", "items": ["wifi", "ac"] },
    { "type": "video_tour", "url": "https://…" }
  ]
}
```

1. `latitude`/`longitude` are **flat** properties on `Listing` (use a nested container).
2. `price.amount` is a **string** in JSON → `Decimal` in the model (no `Double` precision loss).
3. Two date formats in one payload.
4. `blocks` → `[ListingBlock]`, an enum with associated values, using the `type` discriminator. **Unknown types** like `video_tour` decode to `.unknown(type: String)` instead of failing the whole payload.
5. Encoding round-trips to an equivalent JSON (same keys and shapes).
6. Pass decoding context (e.g. the default currency) through `CodingUserInfoKey`.

**Tests:** golden-file decode. Round-trip. An unknown block doesn't fail decoding. A malformed price fails with a `DecodingError.dataCorrupted` whose `codingPath` points to `price.amount`.

**Interview drill**
- `keyDecodingStrategy = .convertFromSnakeCase` vs explicit `CodingKeys`: what breaks with acronyms like `listingURL`?
- How do you keep a long-lived app resilient to server-side enum additions?
- Where does synthesized `Codable` code come from, and why isn't it a macro?

**Read first:** Apple docs, [Encoding and Decoding Custom Types](https://developer.apple.com/documentation/foundation/encoding-and-decoding-custom-types). *Advanced Swift*, ch. "Encoding and Decoding".

---

# Tier 5: Advanced language features

## 20. Scoped warning control with `@diagnose` (L3, Swift 6.4)

**Concept:** diagnostic groups and per-declaration warning control (SE-0522), on top of module-level flags (SE-0443) and SwiftPM settings (SE-0480).

**Scenario (this connects directly to SwiftMigrator).** You're migrating completion-handler APIs to async. The old API is deprecated, the module treats all warnings as errors, and one legacy adapter must keep compiling during the migration.

**Task.**

1. In `Package.swift`, set the `Language` target to:
   ```swift
   swiftSettings: [
       .treatAllWarnings(as: .error),
   ]
   ```
2. Deprecate the legacy API:
   ```swift
   @available(*, deprecated, renamed: "fetchListing(id:)")
   func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void)
   ```
3. Build with `-print-diagnostic-groups` (or read the `[#GroupName]` suffix in the diagnostics) and find the group name of the deprecation warning.
4. Make `LegacyListingAdapter` compile **without** changing module settings, using:
   ```swift
   @diagnose(DeprecatedDeclaration, as: warning, reason: "Removed after SwiftMigrator batch 3")
   ```
   Then refine a nested method to `as: ignored`. Then put one back to `as: error` and record what the compiler reports.
5. Prove the limits. Try to use `@diagnose` to suppress a real **error** (e.g. a type mismatch) and record the result. Which declarations can carry the attribute? Try it on an `import`, an accessor and an extension.
6. **Platform angle:** write a script (or a SwiftSyntax snippet) that lists every `@diagnose(... reason: ...)` in the repo as a migration-debt report. Note in your log why `reason:` must be a static string with no interpolation.

**Tests:** behavior tests for the adapter. The diagnostic behavior is checked by a build. Record the exact compiler output in your notes.

**Interview drill**
- Why is scoped warning control better than `-suppress-warnings` or module-wide `-Wwarning` in a large monorepo?
- How would you use diagnostic groups as a **ratchet** in CI during a migration?

**Read first:** [SE-0522](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0522-source-warning-control.md), [SE-0443](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0443-warning-control-flags.md), [SE-0480](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0480-swiftpm-warning-control.md). Kodeco, [What's New in Swift 6.4?](https://www.kodeco.com/53754585-what-s-new-in-swift-6-4).

---

## 21. Property wrappers (L3)

**Concept:** `wrappedValue`, `projectedValue`, initialization forms, composition and wrappers on parameters (SE-0293).

**Task.**

1. `@Clamped(1...16) var guests: Int`:
   - clamps on init **and** on set
   - `$guests` projects a `ClampReport` (`wasClamped: Bool`, `lastRawValue: Int?`)
2. `@Trimmed var title: String` (trims whitespace and newlines).
3. Compose `@Trimmed @NonEmpty var title: String`. Which wrapper is outermost? Prove the order matters with a test where swapping the attributes changes behavior.
4. A parameter wrapper: `func rename(@Trimmed _ title: String)`. What is `$title` inside the function?
5. Expand by hand, in a comment, what the compiler generates for `@Clamped(1...16) var guests = 20` (the backing `_guests`, the computed `guests` and `$guests`).
6. Explain why `@Clamped` must be a struct to keep `Listing` a value type, and what changes if it were a class.

**Tests:** clamping on init and on set. Projected report. Composition order. Parameter wrapper.

**Interview drill**
- Property wrappers vs macros (`@Observable` replaced the `@Published` approach): what can a wrapper **not** do that a macro can?
- Why can't a property wrapper easily access its enclosing instance (and what does the private `_enclosingInstance` subscript do)?

**Read first:** Swift book, [Properties → Property Wrappers](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/properties/#Property-Wrappers). [SE-0258](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0258-property-wrappers.md), [SE-0293](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0293-extend-property-wrappers-to-function-and-closure-parameters.md).

---

## 22. Result builders (L4)

**Concept:** building an embedded DSL with every builder method, and understanding how the compiler transforms the closure body.

**Task.** A type-safe search query DSL:

```swift
let query = SearchQuery {
    Destination("Buenos Aires")
    Guests(4)
    if includePets { PetsAllowed() }
    if flexible { DateRange.flexible(weeks: 2) } else { DateRange(checkIn, checkOut) }
    for amenity in requiredAmenities { Amenity(amenity) }
    if #available(iOS 27, *) { GlassPreview() }
    "loft"                       // plain strings become keyword filters
}
```

Implement `@resultBuilder enum SearchQueryBuilder` with:

- `buildExpression` (overloads for `QueryComponent` and `String`)
- `buildBlock` / `buildPartialBlock`
- `buildOptional`, `buildEither(first:)` / `buildEither(second:)`
- `buildArray`
- `buildLimitedAvailability`
- `buildFinalResult`: produces a **validated** `SearchQuery` (e.g. exactly one `Destination`)

Stretch: make "two `Destination`s" a **compile-time** error instead of a runtime one, using `buildPartialBlock` overloads with marker types.

**Tests:** each control-flow form produces the expected components. The validation in `buildFinalResult` catches the error cases.

**Interview drill**
- Write on a whiteboard the code the compiler generates for an `if/else` inside a builder closure.
- Why does SwiftUI's `ViewBuilder` need `buildLimitedAvailability`?
- Builders vs plain arrays of components: what do you gain, and what does it cost (type-checking time, diagnostics)?

**Read first:** Swift book, [Result Builders](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/advancedoperators/#Result-Builders). [SE-0289](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0289-result-builders.md), [SE-0348](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0348-buildpartialblock.md).

---

## 23. Macros (L4)

**Concept:** compile-time code generation with SwiftSyntax: freestanding and attached macros, roles, diagnostics and expansion testing.

**Task.** Create a macro target (`swift package init --type macro` as a reference, then merge it into your package).

1. **Freestanding expression macro** `#listingURL("https://…")` that validates the string **at compile time** and expands to a non-optional `URL`. Invalid input → a custom diagnostic that points at the argument, with a fix-it if you can.
2. **Attached peer macro** `@AddAsync`: applied to a completion-handler function, it generates the `async throws(E)` version (this is *exactly* the SwiftMigrator migration, done at compile time):
   ```swift
   @AddAsync
   func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void)
   // expands to (peer):
   // func fetchListing(id: ListingID) async throws(ListingError) -> Listing { … }
   ```
   Emit diagnostics when it's applied to something it can't handle (no completion parameter, non-`Result` completion, not a function).
3. In Xcode, right-click `@Observable` on a model → **Expand Macro**. List every macro role it uses (`member`, `memberAttribute`, `extension`, plus the accessor macros it adds) and write one sentence about each.

**Tests:** `assertMacroExpansion` for valid expansions **and** for each diagnostic (use `SwiftSyntaxMacrosTestSupport`, or `SwiftSyntaxMacrosGenericTestSupport` with a Swift Testing failure handler).

**Interview drill**
- Macros vs property wrappers vs result builders vs codegen scripts: when do you pick each?
- Why are macros sandboxed and run as a separate process? What can't they see (types, other files)?
- What's the build-time cost of swift-syntax, and how do prebuilt swift-syntax binaries mitigate it?

**Read first:** Swift book, [Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/). WWDC23 [Write Swift macros](https://developer.apple.com/videos/play/wwdc2023/10166/) and *Expand on Swift macros*. [SE-0382](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0382-expression-macros.md), [SE-0389](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0389-attached-macros.md).

---

# Tier 6: Ownership and performance

> Put Ex 24–30 in `Sources/Ownership/`. Many key results here are **compile errors**. Keep a `CompileFailures.md` (or commented blocks) with the exact error text for each rule you hit. Interviewers love "what does the compiler say if…".

## 24. Noncopyable types: `ReservationLock` (L4)

**Concept:** `~Copyable`, unique ownership, `deinit` on structs, `consuming` methods and `discard self` (SE-0390).

**Task.**

```swift
struct ReservationLock: ~Copyable {
    let listingID: Int
    let token: UInt64

    init(acquiring listingID: Int) throws(LockError)   // registers in a global registry
    consuming func release() -> ReleaseReceipt          // explicit release, no double release
    deinit                                              // safety net: force-release if dropped
}
```

1. Create a global lock registry that's safe under Swift 6 strict concurrency (hint: `Mutex` from the `Synchronization` module, which is itself `~Copyable`).
2. `release()` must **not** run `deinit` afterwards. Use `discard self`, and record the restriction the compiler places on `discard` (what the stored properties may contain).
3. Collect the compile errors for each of these (comment them out after recording):
   - `let b = lock; lock.release()` (use after move)
   - `lock.release(); lock.release()`
   - putting a lock into an `[ReservationLock]` (`Array` requires `Copyable`; Ex 30 fixes this)
   - capturing the lock in an escaping closure
4. Write a short note on the difference between this and a `final class` lock with `deinit`.

**Tests:** dropping a lock releases it (registry is empty after the scope). `release()` releases exactly once. Acquiring the same listing twice throws `LockError.alreadyHeld`.

**Interview drill**
- What guarantees does `~Copyable` give that a class with `deinit` can't (no shared ownership, deterministic destruction, no refcounting)?
- Where's this pattern used in the stdlib/system (`Mutex`, `Atomic`, file descriptors in `swift-system`)?

**Read first:** WWDC24 [Consume noncopyable types in Swift](https://developer.apple.com/videos/play/wwdc2024/10170/). [SE-0390](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md).

---

## 25. `borrowing`, `consuming`, `inout` and the `consume`/`copy` operators (L4)

**Concept:** parameter ownership conventions (SE-0377) and explicit lifetime control (SE-0366 `consume`, SE-0377 `copy`).

**Task.**

1. With `ReservationLock`, write `inspect(_ l: borrowing ReservationLock)`, `transfer(_ l: consuming ReservationLock) -> Handoff` and `renew(_ l: inout ReservationLock)`. For each, record what the caller can do with the lock afterwards.
2. **Copyable types too.** Use your CoW `AvailabilityCalendar` from Ex 06 and its `_storageID`:
   - Pass a calendar to `func appendingBlock(_ c: consuming AvailabilityCalendar) -> AvailabilityCalendar` with `consume cal` at the call site and show that **no** buffer copy happens (the storage ID is unchanged → the reference stayed unique).
   - Do the same **without** `consume` while `cal` is still used later. Show that a copy happens.
3. Show that a `borrowing` parameter of a **Copyable** type can't be implicitly copied, and fix it with `copy x`.
4. Partial consumption (SE-0429): consume one field out of a noncopyable struct **without** a `deinit`, then add a `deinit` and record why it stops compiling.
5. Know the defaults: what convention do `init` parameters, setter `newValue` and ordinary function parameters use?

**Tests:** storage-identity tests for step 2 (this is the measurable proof that ownership annotations matter for performance).

**Interview drill**
- `consuming` vs `inout`: both let you mutate. What's the difference for the caller?
- Why are ownership modifiers on Copyable parameters an ABI-affecting change?
- Explain `consume` in terms of ARC traffic.

**Read first:** [SE-0377](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0377-parameter-ownership-modifiers.md), [SE-0366](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0366-move-function.md), [SE-0429](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0429-partial-consumption.md).

---

## 26. Typestate with noncopyable types: the reservation state machine (L4)

**Concept:** making illegal state transitions **unrepresentable** by consuming the old state.

**Task.** Do it two ways, then compare.

**A. Noncopyable enum**

```swift
enum Reservation: ~Copyable {
    case draft(DraftInfo)
    case confirmed(ConfirmedInfo, lock: ReservationLock)
    case cancelled(CancelledInfo)

    consuming func confirm(payment: PaymentToken) -> Transition
    consuming func cancel(reason: String) -> Transition
    var status: String { get }            // borrowing switch (SE-0432)
}

enum Transition: ~Copyable {
    case moved(Reservation)
    case rejected(Reservation, reason: RejectReason)   // you get the reservation back!
}
```

Why not `throws`? Write down why a failing consuming transition can't just throw a typed error that carries the reservation. (Hint: what does `Error` require of its conforming types?)

**B. Typestate structs**

```swift
struct DraftReservation: ~Copyable     { consuming func confirm(...) throws(ConfirmError) -> ConfirmedReservation }
struct ConfirmedReservation: ~Copyable { consuming func cancel(...) -> CancelledReservation }
struct CancelledReservation            { /* terminal, Copyable */ }
```

Now `cancel()` on a draft doesn't even compile.

**Comparison memo:** what moves from runtime checks to compile-time checks in B? What's lost (heterogeneous storage, persistence, SwiftUI binding)? Which would you ship, and where?

**Tests:** every legal path. `rejected` returns a usable reservation. The lock moves into `.confirmed` and is released on cancel (registry check). Illegal transitions in B are documented compile errors.

**Interview drill**
- `switch consume self` vs a borrowing `switch self`: when do you need each?
- How is this better than an `enum State` plus `precondition` checks?

**Read first:** [SE-0390](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md), [SE-0432](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0432-noncopyable-switch.md). WWDC24 *Consume noncopyable types in Swift* (the typestate section).

---

## 27. Noncopyable generics: `Box<T: ~Copyable>` (L5)

**Concept:** suppressing the implicit `Copyable` requirement in generics and protocols (SE-0427), plus conditional copyability.

**Task.**

```swift
struct Box<T: ~Copyable>: ~Copyable {
    var value: T
}
extension Box: Copyable where T: Copyable {}
```

1. Add, in the right extensions, `consuming func unwrap() -> T`, `func withValue<R>(_ body: (borrowing T) -> R) -> R` and `consuming func map<U: ~Copyable>(_ f: (consuming T) -> U) -> Box<U>`.
2. **The trap:** write `extension Box { func peek() … }` with no `where T: ~Copyable`. What's implicitly assumed? Record what happens when you call `peek()` on `Box<ReservationLock>`.
3. `protocol Resource: ~Copyable { consuming func close() }`, then `func closeAll<R: Resource & ~Copyable>(_ r: consuming R)`. Make `ReservationLock` conform.
4. `Optional<ReservationLock>`: use `take()` to move the lock out of a stored optional field in a `~Copyable` struct, leaving `nil`.
5. Make `Box` conditionally `Sendable`.

**Tests:** `Box<Int>` is copyable (copy it and mutate the copy independently). `Box<ReservationLock>` moves correctly and releases exactly once. `take()` leaves `nil`.

**Interview drill**
- Why did Swift make `Copyable` an *implicit* requirement everywhere, and spell suppression as `~Copyable` instead of adding a `Copyable` protocol you opt into?
- `T: ~Copyable` means "T **may** be noncopyable". Why isn't it "T must be noncopyable"?

**Read first:** [SE-0427](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0427-noncopyable-generics.md), [SE-0437](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0437-noncopyable-stdlib-primitives.md).

---

## 28. Noncopyable types conforming to `Equatable` / `Comparable` / `Hashable` (L5, Swift 6.4)

**Concept:** SE-0499 lets the basic protocols drop their `Copyable` requirement. The requirements now take `borrowing` parameters.

**Task.**

1. `struct SecretToken: ~Copyable, Hashable, CustomStringConvertible` (holds key bytes, redacts itself in `description`). Implement `==` with `borrowing` parameters, `hash(into:)` and `description`.
2. Check whether the compiler **synthesizes** `Equatable`/`Hashable` for a noncopyable struct with Hashable fields in your toolchain. If not, write the conformance by hand and record the diagnostic.
3. `extension Box: Equatable where T: Equatable & ~Copyable` and the same for `Hashable` (from Ex 27).
4. Use the stdlib extensions SE-0499 adds: compare `SecretToken?` values with `==`, interpolate a token in a string (`"\(token)"`), and call `String(describing:)`. All of this must work **without copying**.
5. `Comparable`: make `ReservationLock` comparable by `token` and write a borrowing `func earliest(_ a: borrowing ReservationLock, _ b: borrowing ReservationLock) -> UInt64`. Why can't you return the lock itself here?
6. Try `Set<SecretToken>` and `[SecretToken: Int]`. Record the errors and explain them: Hashable is necessary but not sufficient, because the collections still require `Copyable` elements and keys.

**Tests:** equality and hashing consistency (`a == b ⇒ hash(a) == hash(b)`), optional equality and redacted descriptions.

**Interview drill**
- Why does making `Equatable` `~Copyable` require `borrowing` parameters in the protocol requirement, and why is this ABI-compatible?
- Why is `LosslessStringConvertible` `~Copyable` but **not** `~Escapable`?

**Read first:** [SE-0499](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0499-support-non-copyable-simple-protocols.md). InfoQ, [Swift 6.4 released](https://www.infoq.com/news/2026/09/swift-6-4-released/).

---

## 29. `InlineArray` and `Span`: the hot-path rewrite and benchmark (L5)

**Concept:** fixed-size inline storage (SE-0453, sugar `[N of T]` from SE-0483), safe non-escapable views (SE-0447 `Span`, `MutableSpan`), lifetime rules (`~Escapable`) and measuring performance properly.

**Task.**

1. **Baseline.** `func weeklyAverages(prices: [Decimal or Double]) -> [Double]` computes a 7-night rolling average over a year of prices, using a temporary `[Double]` window allocated per step. Run it 1M times.
2. **Rewrite.** Use `InlineArray<7, Double>` (also write it as `[7 of Double]`) for the window. Read it through a `Span<Double>`:
   ```swift
   func average(_ window: Span<Double>) -> Double
   ```
   Also feed it the `span` of an `Array` and of a `UniqueArray` (Ex 30). The function is storage-agnostic.
3. Normalize prices **in place** through a `MutableSpan<Double>`.
4. **Lifetime rules.** Record the compile errors when you try to return a `Span` from a function that builds a local array, store a `Span` in a class property, or capture it in an escaping closure. Explain `~Escapable` in one paragraph.
5. **Semantics.** `InlineArray` is **eagerly** copied (no CoW) and isn't a `Sequence`/`Collection`. Show both facts, then explain when `InlineArray` is *slower* than `Array` (large N passed around by value).
6. **Measure properly.** Release build (`-c release`), several runs, `ContinuousClock` and a `blackHole` to defeat dead-code elimination. Better: `package-benchmark` with wall-clock **and malloc-count** metrics. Report median, p90 and allocations per call for both versions in a table.

**Tests:** both implementations produce identical results (property test over random inputs). `MemoryLayout<InlineArray<7, Double>>.size == 56`. The benchmark lives in `Benchmarks/`, not in unit tests.

**Interview drill**
- `Span` vs `UnsafeBufferPointer`: what safety does `Span` add (bounds checks, lifetime dependency, no escape)? What does it cost?
- When should a hot path take `Span<T>` instead of `some Collection<T>` or `[T]`?
- How do you prove a performance claim in a code review?

**Read first:** WWDC25 [Improve memory usage and performance with Swift](https://developer.apple.com/videos/play/wwdc2025/312/). [SE-0447](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0447-span-access-shared-contiguous-storage.md), [SE-0453](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0453-vector.md), [SE-0483](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0483-inline-array-sugar.md).

---

## 30. `UniqueArray`, `RigidArray` and `UniqueBox`: owning containers (L5, Swift 6.4)

**Concept:** heap-allocated, uniquely owned containers with **no copy-on-write and no refcounting**, which can hold noncopyable elements (SE-0517, SE-0527). Accessors use `borrow` / `mutate` (SE-0507).

**Task.**

1. **`LockPool`** (fixes Ex 24 step 3):
   ```swift
   struct LockPool: ~Copyable {
       private var locks: UniqueArray<ReservationLock>
       mutating func acquire(_ listingID: Int) throws(LockError)
       mutating func release(listingID: Int) -> ReleaseReceipt?     // remove(at:) + consuming release
       consuming func releaseAll() -> [ReleaseReceipt]               // drain with popLast()
   }
   ```
   Check whether your toolchain exposes `UniqueArray` from the standard library or through `import Containers`. SE-0527 mentions both, so record which one it is.
2. **Backpressure with `RigidArray`:** a fixed-capacity `HoldQueue` that uses `pushLast(_:)` (it returns the element back when full) to reject holds once at capacity without allocating.
3. **`UniqueBox` for recursive noncopyable data:** a singly linked list of `ReservationLock`s:
   ```swift
   struct LockList: ~Copyable {
       struct Node: ~Copyable { var lock: ReservationLock; var next: UniqueBox<Node>? }
       private var head: UniqueBox<Node>?
       mutating func push(_ lock: consuming ReservationLock)
       mutating func pop() -> ReservationLock?
   }
   ```
   Use `UniqueBox.value` (borrow/mutate) and `consume()`. Add a `deinit` or iterative drop, and explain why the default recursive destruction can overflow the stack for very long lists.
4. **Borrow/mutate accessors:** expose `LockPool.first` as a `borrow` accessor and `LockPool.last` as a `mutate` accessor that returns `&locks[...]`. Explain how this differs from `get`/`set` (no copy, and the value can be noncopyable).
5. **Benchmark:** `UniqueArray<Int>` vs `Array<Int>` for 10M appends and in-place updates. Did removing the uniqueness check and CoW change anything measurable? Report honestly, even if the difference is small.
6. **Stretch, `Iterable` (SE-0516):** iterate `UniqueArray<ReservationLock>` with borrowing iteration (no copies) and compare it with `for i in locks.indices { locks[i] … }`.

**Tests:** pool acquire/release/drain releases every lock exactly once (registry). `RigidArray` overflow is handled without trapping. The linked list pushes/pops in LIFO order and drops 1M nodes without crashing.

**Interview drill**
- `Array` vs `UniqueArray` vs `RigidArray` vs `InlineArray`: when do you pick each? (A 2×2 of heap/inline × growable/fixed is a great whiteboard answer.)
- `UniqueBox<T>` vs `final class Box<T>` vs `indirect enum`: compare allocation, refcounting, copyability and thread-safety.
- Why doesn't `UniqueArray` conform to `ExpressibleByArrayLiteral` or `Sequence`?

**Read first:** [SE-0517](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0517-uniquebox.md), [SE-0527](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0527-rigidarray-uniquearray.md), [SE-0507](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0507-borrow-accessors.md), [SE-0516](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0516-borrowing-sequence.md).

---

# Capstone: StayKit, a booking engine core

**Goal:** one coherent, tested SPM module that you can **demo and walk through in 15 minutes** in an iOS-depth or coding interview. Each component exists because it's the *right* tool, not to show off. In the interview, you'll be asked "why not just X?" for every choice.

## Product spec

A guest searches listings, gets a price quote, places a temporary hold, pays and receives a confirmed reservation, or cancels. Hosts' listings arrive as JSON from a legacy API.

```
 JSON (legacy API) ──► Codable import ──► Repository<Listing> (some/any)
                                               │
 SearchQuery DSL (result builder) ─────────────┤
                                               ▼
                                   QuoteEngine (PricingRule enum,
                                   InlineArray + Span hot path)
                                               │
                                               ▼
   DraftReservation ~Copyable ──hold──► ReservationLock ~Copyable (LockPool: UniqueArray)
           │ consuming confirm() throws(BookingError)
           ▼
   ConfirmedReservation ~Copyable ──cancel()──► CancelledReservation
           │
           ▼
   EventSink<BookingEvent> (type-erased fan-out) ──► Receipt (Codable)
```

## Required components (each one maps to the exercises)

| # | Component | Concepts it proves | From Ex |
| --- | --- | --- | --- |
| C1 | `Tagged<Tag, Raw>` IDs: `ListingID`, `HostID`, `ReservationID` | phantom types, conditional conformance, `Codable` | 14 |
| C2 | `Listing` (value type) holding `AvailabilityCalendar` (CoW). `Host` (class, identity) | value vs reference, CoW | 01, 06 |
| C3 | `ListingImporter`: decodes the legacy JSON with polymorphic `blocks` and unknown-type resilience | advanced `Codable` | 19 |
| C4 | `protocol Repository<Entity>`, `InMemoryRepository`. Factory returns `some Repository<Listing>`. Services store `any Repository<Listing>` | PATs, primary associated types, `some` vs `any`, 6.4 `any P?` | 11, 12 |
| C5 | `SearchQuery { … }` DSL with compile-time or `buildFinalResult` validation. Results sorted with key-path `SortRule`s, evaluated lazily with `prefix(n)` | result builders, key paths, lazy sequences | 09, 10, 22 |
| C6 | `PricingRule` indirect enum + simplifier. `QuoteEngine` uses `InlineArray`/`Span` for nightly windows | pattern matching, `InlineArray`, `Span` | 02, 29 |
| C7 | `GuestRequest` with `@Clamped(1...16) var guests` and `@Trimmed var note` | property wrappers | 21 |
| C8 | `FormValidator<each Field>` validates the booking form (dates, guests, payment token) in one typed call | parameter packs | 16 |
| C9 | Error domain `ListingError`, `PaymentError`, `BookingError` with typed throws. `withRetry` preserves the type. The legacy callback API is bridged with `Result` | typed throws, `Result` | 17, 18 |
| C10 | `ReservationLock: ~Copyable` + `LockPool` (`UniqueArray`). Typestate `DraftReservation → ConfirmedReservation → CancelledReservation`, with the lock **moved** into the confirmed state | `~Copyable`, `consuming`/`borrowing`, typestate, noncopyable generics, `UniqueArray` | 24–27, 30 |
| C11 | `PaymentToken: ~Copyable, Hashable` (redacted `description`) | 6.4 noncopyable conformances | 28 |
| C12 | `AnyEventSink<BookingEvent>`, a `Hashable` erased sink stored in a `Set`. Listeners don't leak (capture lists) | type erasure, escaping closures | 08, 15 |
| C13 | `LegacyListingAdapter` behind `@diagnose(DeprecatedDeclaration, as: warning, reason: …)` in a warnings-as-errors module. Optional: `@AddAsync` macro generates its async twin | `@diagnose`, macros | 20, 23 |
| C14 | `Receipt` struct with a `private var auditTrail: [String] = []`. Show that Swift 6.4's memberwise init no longer asks for it (SE-0502) | 6.4 memberwise init | — |
| C15 | Everything is `Sendable` where it crosses a boundary, built in the Swift 6 language mode with zero warnings (except the documented `@diagnose` scope) | strict concurrency (bridge to Day 5) | — |

## Public API sketch (signatures only; you implement)

```swift
public struct BookingService: ~Copyable {
    public init(listings: any Repository<Listing>, events: AnyEventSink<BookingEvent>, lockCapacity: Int)

    public func search(@SearchQueryBuilder _ query: () -> SearchQuery) -> [Listing]
    public func quote(_ id: ListingID, stay: Range<Date>, guests: GuestRequest) throws(ListingError) -> Quote

    public mutating func hold(_ quote: Quote) throws(BookingError) -> DraftReservation
    public mutating func confirm(_ draft: consuming DraftReservation,
                                 paying token: consuming PaymentToken) throws(BookingError) -> ConfirmedReservation
    public mutating func cancel(_ reservation: consuming ConfirmedReservation,
                                reason: String) -> CancelledReservation
}
```

Design questions to answer **in the README** (these are the interview follow-ups):

1. Why is `BookingService` noncopyable? What would go wrong if two copies shared one `LockPool`?
2. `confirm` consumes the draft. On a `BookingError`, how does the caller get the draft back? (Recall the Ex 26 `Transition` vs typed-throws discussion. Pick one and justify it.)
3. Why does the service store `any Repository<Listing>` while the factory returns `some`?
4. Why does `QuoteEngine` take `Span<Double>` and not `[Double]`?
5. Which errors are typed and which aren't, and why (public evolution vs closed domains)?

## Acceptance tests (Swift Testing)

- `@Suite("Search")`: DSL control flow; key-path multi-sort; lazy `prefix` evaluates ≤ N listings (counter).
- `@Suite("Pricing")`: parameterized quotes over 10+ rule trees; the `InlineArray` path equals the `Array` reference implementation.
- `@Suite("Booking lifecycle")`: happy path; payment declined → draft is recoverable; double confirm is impossible (documented compile error); cancel releases the lock (registry empty); dropping a draft releases its lock (`deinit`).
- `@Suite("Import")`: golden JSON; unknown block types survive; malformed price → `DecodingError` with the right `codingPath`.
- `@Suite("Events")`: sinks deduplicate in a `Set`; no leaks (`weak` check after scope).
- `@Suite("Errors")`: every `BookingError` case is reachable; `withRetry` preserves the type.
- One **exit test** proving the exclusivity trap from Ex 07 can't happen through the public API (or documenting where it could).
- A **benchmark** in `Benchmarks/` for the quote hot path: median / p90 / mallocs, before vs after.

## Definition of done

- [ ] `swift build -c release` and `swift test` pass in the Swift 6 language mode; no warnings outside the documented `@diagnose` scope.
- [ ] Every public type has a doc comment that says *why* it's a struct, enum, class or `~Copyable`.
- [ ] `notes/swift-6.4-language.md` has your answers to the 5 README design questions.
- [ ] A recorded 15-minute walkthrough (to yourself or the agent) using the script below.
- [ ] You can rewrite any 3 randomly chosen components from scratch, without notes, in 45 minutes.

## 15-minute interview walkthrough script

| Minute | Show | Say (the one-liner you must nail) | Expect the follow-up |
| --- | --- | --- | --- |
| 0–2 | Architecture diagram | "Value types at the edges, unique ownership for anything that must happen exactly once." | "Why not classes plus a coordinator?" |
| 2–4 | `Listing` + `AvailabilityCalendar` | "Value semantics by construction; CoW so copies are O(1) until mutation." | "Is CoW thread-safe?" |
| 4–6 | `Repository` + `some`/`any` | "`some` where the type is fixed and I want static dispatch; `any` where I need to store or swap it." | "What does the existential cost?" (40 bytes, witness table, possible heap box) |
| 6–8 | `SearchQuery` DSL + `FormValidator` | "Result builders for declarative input; parameter packs for statically typed N-ary validation, no `Any`." | "Show the desugared builder code." |
| 8–10 | Typed throws + `Result` bridge | "Typed throws for closed internal domains; untyped at public boundaries for evolution." | "How do you add an error case later?" |
| 10–13 | Lock + typestate + `LockPool` | "The compiler, not code review, guarantees a reservation is confirmed once and its lock is released once." | "What happens on a failed transition?" / "Why not `deinit` on a class?" |
| 13–15 | Benchmark table (`InlineArray`/`Span`, `UniqueArray`) | "I measured: release build, malloc counts, median and p90. Here's what changed and what didn't." | "When would `InlineArray` be slower?" |

---

## Progress checklist

- [ ] 01 Value vs reference
- [ ] 02 Pattern matching
- [ ] 03 Optionals
- [ ] 04 Dispatch
- [ ] 05 Module selectors
- [ ] 06 Copy-on-write
- [ ] 07 `inout` & exclusivity
- [ ] 08 Closures & captures
- [ ] 09 Key paths
- [ ] 10 Lazy sequences
- [ ] 11 Primary associated types
- [ ] 12 `some` vs `any`
- [ ] 13 Generic constraints
- [ ] 14 Conditional conformance
- [ ] 15 Type erasure
- [ ] 16 Parameter packs
- [ ] 17 `Result`
- [ ] 18 Typed throws
- [ ] 19 Advanced `Codable`
- [ ] 20 `@diagnose`
- [ ] 21 Property wrappers
- [ ] 22 Result builders
- [ ] 23 Macros
- [ ] 24 `~Copyable` lock
- [ ] 25 `borrowing` / `consuming`
- [ ] 26 Typestate
- [ ] 27 Noncopyable generics
- [ ] 28 Noncopyable `Equatable`/`Hashable`
- [ ] 29 `InlineArray` + `Span` benchmark
- [ ] 30 `UniqueArray` / `UniqueBox`
- [ ] Capstone: StayKit

## Resources (in study order)

- [The Swift Programming Language](https://docs.swift.org/swift-book/): Structures and Classes, Enumerations, Closures, Protocols, Generics, Opaque and Boxed Protocol Types, Error Handling, Result Builders, Macros
- *Advanced Swift*, objc.io, 5th ed. (predates typed throws and noncopyable types)
- WWDC22 [Embrace Swift generics](https://developer.apple.com/videos/play/wwdc2022/110352/) · [Design protocol interfaces in Swift](https://developer.apple.com/videos/play/wwdc2022/110353/)
- WWDC23 [Write Swift macros](https://developer.apple.com/videos/play/wwdc2023/10166/)
- WWDC24 [Consume noncopyable types in Swift](https://developer.apple.com/videos/play/wwdc2024/10170/) → SE-0390, SE-0427
- WWDC25 [Improve memory usage and performance with Swift](https://developer.apple.com/videos/play/wwdc2025/312/) → SE-0447, SE-0453
- SE-0413 (typed throws), SE-0393 (parameter packs) on [Swift Evolution](https://www.swift.org/swift-evolution/)
- [What's New in Swift 6.4?](https://www.kodeco.com/53754585-what-s-new-in-swift-6-4) (Kodeco) · [InfoQ release summary](https://www.infoq.com/news/2026/09/swift-6-4-released/)
- Swift 6.4 proposals used above: SE-0491, SE-0499, SE-0502, SE-0507, SE-0516, SE-0517, SE-0521, SE-0522, SE-0527
- Extra practice: [Exercism Swift track](https://exercism.org/tracks/swift)
