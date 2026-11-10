# Swift 6.4 Language

The quick-review companion to [swift-6.4-language-exercises.md](swift-6.4-language-exercises.md). The full answers are in [swift-6.4-language-exercises-responses.md](swift-6.4-language-exercises-responses.md). 

## Milestone: explain these without notes

**Value semantics.** Each variable holds an independent value: mutating one can never be observed through another. It's a property of behavior, not of `struct`. A struct holding a class reference shares that object. Make it a value type by construction (all stored properties are values), or add copy-on-write: share the buffer on copy, clone it on mutation only if `isKnownUniquelyReferenced` says it's shared.

**`some` vs `any`.** `some P` is one fixed concrete type, hidden from the reader: the callee chooses it in return position, the caller in parameter position (where it's a generic). It's static dispatch and can be specialized. `any P` is an existential box: 40 bytes on 64-bit (a 3-word buffer + metadata + witness table), heap-allocated beyond 3 words, dynamic dispatch, and associated types erased. Default to `some`; use `any` for heterogeneous storage or runtime injection.

**Typed throws.** `throws(E)` declares the exact error. `throws` ≡ `throws(any Error)`, and non-throwing ≡ `throws(Never)`. There are no implicit conversions between error types (you map them explicitly), and generics carry `E` through (`withRetry<T, E>`), which replaces `rethrows`. Use it for closed internal domains. Public APIs whose failure modes may grow should stay untyped, because adding a case breaks exhaustive `catch`.

**Ownership.**
- `~Copyable`: one owner, moves on assignment, use after move is a compile error, and a struct `deinit` runs deterministically.
- `borrowing`: read and keep. `consuming`: take ownership. `inout`: exclusive access, then give it back.
- `consume x`: forward the +1 reference, with no retain/release.
- `copy x`: an explicit copy.
- `discard self`: end the lifetime without running `deinit`.
- `Span`: a `~Escapable`, bounds-checked view that can't outlive its storage.
- `InlineArray`: inline fixed-size storage with eager copies.
- `UniqueArray` / `UniqueBox`: owned heap storage with no CoW and no refcount.

## Per exercise

### 01 Value vs reference
- **Concept:** value semantics comes from what a type stores and how it behaves, not from the `struct` keyword.
- **Gotcha:** `let broken = BrokenListing(…); broken.gallery.urls.append(x)` compiles, because `let` only freezes the reference.
- `struct PhotoGallery { var urls: [URL] }   // replaces the class: same call sites, value semantics`

### 02 Pattern matching
- **Concept:** patterns nest (`case let (a, .percentOff(b, inner)) where …`), and `case P:` calls `P ~= subject`.
- **Gotcha:** 50% off twice is 75%, not 100%. Only merge discounts when `a + b - ab/100` is an integer.
- `static func ~= (pattern: StayLength, value: Int) -> Bool { pattern.nights.contains(value) }`

### 03 Optionals
- **Concept:** `Optional` is an enum plus sugar; `??` is an `@autoclosure` function that only evaluates the right side when the left is `nil`.
- **Gotcha ⚙️:** `rhs: @autoclosure () throws(E) -> T` gives *"generic parameter 'E' could not be inferred"*. Use `rethrows`, as the stdlib does.
- `switch dict[key] { case .none: .missing; case .some(.none): .explicitNil; case .some(.some(let v)): .value(v) }`

### 04 Dispatch
- **Concept:** requirements go through witness tables, extension-only methods are static, and class methods go through vtables.
- **Gotcha:** a subclass's `summary()` *shadows* the protocol extension's default instead of overriding it, so generic and `any` calls still print "generic summary".
- `open class FixedBaseCard: Describable { open func summary() -> String { "base" } }   // gets a vtable slot`

### 05 Module selectors (6.3+)
- **Concept:** `Module::Name` picks a declaration's module. For an unqualified name it starts at that module's top level.
- **Gotcha ⚙️:** `value.Module::member` compiles but calls the **wrong** extension on 6.3.2 and 6.4.2 (repro in `scripts/compiler-bugs/`). Top-level names and nested types work.
- `func importedListing() -> Listing::Listing   // module and type share a name`

### 06 Copy-on-write
- **Concept:** a copy shares the buffer; `isKnownUniquelyReferenced` before a mutation decides whether to clone it.
- **Gotcha ⚙️:** a snapshot on every mutation (an undo history) costs a full copy *per iteration* (50 copies for 50 days). One extra reference costs only one copy.
- `_modify { makeUnique(); yield &storage.days[day] }`

### 07 inout and exclusivity
- **Concept:** `inout` is copy-in/copy-out under exclusive access, checked statically where possible and at runtime otherwise.
- **Gotcha ⚙️:** passing a `didSet` property `inout` and mutating it 3 times fires `didSet` **once**. `transfer(&x, &x)` → *"inout arguments are not allowed to alias each other"*.
- `await #expect(processExitsWith: .failure) { E07.triggerExclusivityViolation() }   // exit test`

### 08 Closures
- **Concept:** closures capture variables (boxes); capture lists capture values at creation time.
- **Gotcha:** `[unowned self]` is only safe if the closure can't outlive `self`. It's fine for `onChange` (owned by self) and a crash for the loader's completion.
- `onChange = { [weak self] in guard let self else { return }; print(self.title) }   // atomic: all or nothing`

### 09 Key paths
- **Concept:** key paths are typed, composable property references; storing a comparator erases the `Value` type.
- **Gotcha ⚙️:** `static let p = (\A.b).appending(path: \B.c)` isn't `Sendable` in Swift 6. Only literals typed `KeyPath<…> & Sendable` can be stored globally.
- `static let titlePath: KeyPath<Listing, String> & Sendable = \Listing.title`

### 10 Lazy sequences
- **Concept:** `lazy` computes on demand and re-computes on every iteration; `LazySequenceProtocol` keeps custom adapters lazy.
- **Gotcha ⚙️:** never add `86_400` to move to the next day: across DST the date drifts to 01:00. Use `calendar.date(byAdding: .day, …)`.
- `extension LazySequenceProtocol { func chunked(by n: Int) -> LazyChunkedSequence<Elements> }`

### 11 Primary associated types
- **Concept:** an associated type is an output of the conformance; the primary one is what callers constrain (`some Repository<Listing>`).
- **Gotcha:** don't make `Entity.ID` primary. It's determined by `Entity`, so a second knob could only contradict it.
- `package protocol Repository<Entity> { associatedtype Entity: Identifiable; associatedtype Entities: Collection = [Entity] where Entities.Element == Entity }`

### 12 some vs any
- **Concept:** an opaque type is one hidden concrete type; an existential is a box that can hold any conforming type.
- **Gotcha ⚙️:** `MemoryLayout<(any P)?>.size == 40`, the same as `any P` (extra inhabitants). Swift 6.4 accepts `any P?`, but `any P & Q?` is rejected; write `any (P & Q)?`.
- `func optionalQuote(_ s: any PricingStrategy?, nights: Int) -> Decimal?   // 6.4 shorthand (SE-0521)`

### 13 Generic constraints
- **Concept:** constrained extensions add members only when their requirements hold, and overloads are resolved at compile time.
- **Gotcha ⚙️:** inside `func f<C: Collection>`, `c.median()` picks the `Collection` overload even for an `Array`. Make it a protocol requirement (a customization point).
- `protocol MedianComputable: Collection where Element: Comparable { func fastMedian() -> Median<Element> }`

### 14 Conditional conformance and phantom types
- **Concept:** `extension Tagged: Hashable where RawValue: Hashable`, with `Tag` never stored, so it costs nothing at runtime (tested).
- **Gotcha:** `ExpressibleByStringLiteral` needs the whole chain (UnicodeScalar → ExtendedGraphemeCluster → String) implemented for a generic raw value.
- `package typealias ListingID = Tagged<Listing, UUID>   // can't be passed as a HostID`

### 15 Type erasure
- **Concept:** you still need a hand-written eraser when the erased type itself must conform (`Hashable`, `Set`) or control its semantics.
- **Gotcha ⚙️:** a closure-based eraser over a stateful struct **shares** state between copies (counts `[1, 2]`). A class box with CoW, or `any EventSink`, keeps value semantics (`[1, 1]`).
- `if !isKnownUniquelyReferenced(&box) { box = box.copy() }; box.send(event)`

### 16 Parameter packs
- **Concept:** `each T` / `repeat` give arbitrary arity with full static typing.
- **Gotcha:** you can't mutate tuple-pack elements in place (put iterators in reference boxes) or `return` from inside a `repeat` expression (use a throwing helper).
- `repeat check(each rules, each values)   // pairs the i-th rule with the i-th value`

### 17 Result
- **Concept:** `Result` is a failure turned into a value: you can store it, collect it and pass it to a callback.
- **Gotcha:** `withCheckedThrowingContinuation` erases the error to `any Error`. Resume a `Result` and call `.get()` to keep `ListingError`.
- `let r = await withCheckedContinuation { c in api.fetch(id) { c.resume(returning: $0) } }; return try r.get()`

### 18 Typed throws
- **Concept:** an exact error type, an exhaustive `catch` with no default, and generic error propagation.
- **Gotcha ⚙️:** there's no implicit conversion: *"thrown expression type 'ListingError' cannot be converted to error type 'BookingError'"*. Map explicitly with `do { … } catch { throw .listing(error) }`.
- `func withRetry<T, E: Error>(attempts: Int, _ op: () throws(E) -> T) throws(E) -> T   // { 42 } needs no try`

### 19 Codable
- **Concept:** nested containers flatten JSON; a discriminator key plus an `.unknown` case gives resilient polymorphism.
- **Gotcha:** `convertFromSnakeCase` turns `listing_url` into `listingUrl`, not `listingURL`. Use explicit `CodingKeys`.
- `throw DecodingError.dataCorruptedError(forKey: .amount, in: priceContainer, debugDescription: …)   // codingPath = price.amount`

### 20 @diagnose (6.4)
- **Concept:** warning control scoped to one declaration and one diagnostic group, nestable and auditable through `reason:`.
- **Gotcha ⚙️:** it only affects **warnings**; real errors stay errors. `@diagnose` doesn't exist on 6.3, so wrap the attribute in `#if compiler(>=6.4)` (SE-0367).
- `@diagnose(DeprecatedDeclaration, as: ignored, reason: "Bridge for callers not yet on async")`

### 21 Property wrappers
- **Concept:** `_x` storage, `x` through `wrappedValue`, `$x` through `projectedValue`; composition applies inside-out.
- **Gotcha ⚙️:** order only matters if the outer wrapper bypasses the inner one's rules. `@Trimmed @NonEmpty "   "` → `""`, while `@NonEmpty @Trimmed` → `"Untitled"`.
- `@Clamped(1...16) package var guests: Int = 1   // $guests is a ClampReport`

### 22 Result builders
- **Concept:** the compiler rewrites the closure body into `buildExpression`, `buildPartialBlock`, `buildEither`, `buildOptional`, `buildArray`, `buildLimitedAvailability` and `buildFinalResult`.
- **Gotcha:** the whole builder closure is type-checked as one expression, so large builders are slow to compile and errors point at the wrong place.
- `static func buildFinalResult(_ c: [QueryComponent]) -> SearchQuery { SearchQuery(validating: c) }`

### 23 Macros
- **Concept:** compile-time SwiftSyntax plugins that see syntax, never types, and emit code, diagnostics and fix-its.
- **Gotcha ⚙️:** `assertMacroExpansion` re-formats the output, so shape the generated code to survive the formatter. `MacroSpec` lives in `SwiftSyntaxMacroExpansion`.
- `@attached(peer, names: overloaded) package macro AddAsync() = #externalMacro(module: "LanguageMacros", type: "AddAsyncMacro")`

### 24 ~Copyable lock
- **Concept:** unique ownership with a deterministic `deinit`; `consuming func release()` + `discard self` releases exactly once.
- **Gotcha ⚙️:** `discard` requires **trivially-destroyed** stored properties (no class references). It's a SIL error, so `-typecheck` misses it.
- `package consuming func release() -> ReleaseReceipt { let r = registry.release(…); discard self; return r }`

### 25 borrowing / consuming / consume / copy
- **Concept:** parameter ownership conventions, plus explicit lifetime control for locals.
- **Gotcha ⚙️:** `appendingBlock(consume cal)` keeps the CoW buffer unique (same `_storageID`). Without `consume`, while `cal` is still used, it's a full copy.
- `static func duplicate(_ c: borrowing Calendar) -> Calendar { copy c }   // `c` alone: "borrowed and cannot be consumed"`

### 26 Typestate
- **Concept:** transitions consume the old state, so illegal transitions become compile errors (typestate structs) or handled values (`Transition`).
- **Gotcha:** `Error` requires `Copyable`, so a failed consuming transition can't throw the noncopyable value back. Return it.
- `switch consume self { case .draft(let info): … return .moved(.confirmed(info, …, lock: lock)) }`

### 27 Noncopyable generics
- **Concept:** `T: ~Copyable` means "may be noncopyable", and `extension Box: Copyable where T: Copyable {}` makes the box as copyable as its contents.
- **Gotcha ⚙️:** an extension without `where T: ~Copyable` silently requires `Copyable` (*"requires that 'Lock' conform to 'Copyable'"*).
- `extension Box where T: ~Copyable { consuming func unwrap() -> T { value } }`

### 28 Noncopyable Equatable/Hashable (6.4)
- **Concept:** the basic protocols accept `~Copyable` with `borrowing` requirements, and conformances are synthesized.
- **Gotcha ⚙️:** in 6.4.2, `CustomStringConvertible`, interpolation and `Optional == Optional` still require `Copyable`. And `#expect(a == b)` doesn't compile with noncopyable operands: write `let eq = a == b; #expect(eq)`.
- `struct SecretToken: ~Copyable, Hashable { private let bytes: [UInt8] }   // == and hash synthesized`

### 29 InlineArray + Span
- **Concept:** inline fixed storage plus a lifetime-checked view: a storage-agnostic hot path with no allocations.
- **Gotcha ⚙️:** use a fair baseline. 204× faster than a new array per step, but **15×** faster than one reused array. Most of the win is the allocation.
- `var window: [7 of Double] = .init(repeating: 0); averages.append(average(window.span))`

### 30 UniqueArray / UniqueBox (6.4)
- **Concept:** owned heap containers with no CoW and no refcount, able to hold noncopyable elements; `borrow`/`mutate` accessors expose storage in place.
- **Gotcha ⚙️:** they're macOS 27-gated, `RigidArray` isn't shipped, `deinit` can't mutate `self`, `mutate` can't return `&uniqueArray[i]`, and a recursive `UniqueBox` node **crashes the optimizer** at `-O`.
- `var value: Element { borrow { return storage.value } mutate { return &storage.value } }`

### Capstone: StayKit
- **Concept:** value types at the edges, and unique ownership for anything that must happen exactly once (a hold, a confirmation, a payment token).
- **Gotcha ⚙️:** `Array(lazyFilterCollection.prefix(1))` ran the predicate 6 times; a single `for` loop with `break` runs it once per element. `.lazy` on `any Collection` doesn't compile, so open the existential through a generic helper.
- `let confirmed = try service.confirm(draft, paying: PaymentToken("tok_ok"))   // consumes the draft AND the token`

## Swift 6.4.2 reality check (what the articles don't tell you)

| Topic | Reality on Swift 6.4.2 / macOS 26 |
| --- | --- |
| `UniqueArray`, `UniqueBox` | stdlib, gated to **macOS 27**; no `Containers` module |
| `RigidArray` | not shipped |
| SE-0499 | `Equatable`/`Comparable`/`Hashable` ✅ (synthesized); `CustomStringConvertible`, `Optional ==` ❌ |
| `discard self` | still requires trivially-destroyed fields (SIL-level error) |
| `mutate` accessors | stored properties and `UniqueBox.value` ✅; `&uniqueArray[i]` ❌; `yielding mutate` experimental |
| `deinit` mutating `self` | ❌ (SE-0544 accepted, not implemented) |
| Member module selectors | compile, resolve wrong (bug, 6.3.2 and 6.4.2) |
| Recursive `UniqueBox` | optimizer crash at `-O` (bug) |
| `for x in InlineArray` | needs `Iterable`, available on macOS 27 |
| `@diagnose` | works as specified; warnings only |
| `any P?` / `some P?` | works; compositions need `any (P & Q)?` |
| SE-0502 memberwise init | on by default in 6.4 (on 6.3, the init is `private` when a `private var x = …` exists) |

## Access control in this repo

- Nothing is `public`: no code outside this package uses it.
- `package` (SE-0386) marks what other targets use: the shared domain, `Tagged`, `AvailabilityCalendar`, the search DSL, `ReservationLock`, `LockPool`, …
- Everything else is `internal`. Tests use `@testable import`.
- Memberwise inits are never visible outside their module, so `package` types used across modules still need a hand-written `package init`. `internal` types use the generated one (e.g. `QuoteEngine` puts defaults on its properties instead of writing an init).
- Protocol requirements can't carry modifiers; a witness must be at least as visible as `min(type, protocol)`.

## Environment notes

- swiftly installed Swift 6.4.2 in `~/Library/Developer/Toolchains`. The global default stays **Xcode's 6.3.2**, and only this repo uses 6.4.2 (`.swift-version`). swiftly added a line to `~/.bash_profile` that sources `~/.swiftly/env.sh`.
- `xcrun swift test --scratch-path .build/xcode-6.3` runs the same package on Xcode's toolchain.
- `scripts/verify-compile-errors.sh` re-checks every quoted compiler error. Rerun it after a toolchain update to see which limitations were lifted.
