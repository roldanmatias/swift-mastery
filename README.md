# swift-mastery

Day 4 of the 4-week plan: Swift 6.4 language core. One SPM package with all 30 exercises, the StayKit capstone, tests, benchmarks and verified compiler-error snippets.

- Exercises: [notes/swift-6.4-language-exercises.md](notes/swift-6.4-language-exercises.md)
- Solutions, theory and interview drills: [notes/swift-6.4-language-exercises-responses.md](notes/swift-6.4-language-exercises-responses.md)
- Study log (one concept, one gotcha and one snippet per exercise): [notes/swift-6.4-language.md](notes/swift-6.4-language.md)

## Toolchain

The repo is pinned to **Swift 6.4.2** through `.swift-version` ([swiftly](https://www.swift.org/install/)). Swift-6.4-only code is wrapped in `#if compiler(>=6.4)`, so the package also builds and tests with Xcode 26.5 (Swift 6.3.2); the 6.4 suites are compiled out there.

`UniqueArray` / `UniqueBox` are availability-gated to **macOS 27**. On macOS 26 their tests compile and are reported as skipped ("Requires macOS 27").

## Access control

Nothing is `public`. Declarations used by another target are `package`, everything else is `internal`, and tests use `@testable import`.

## Commands

```bash
swift test                                   # all suites (Swift 6.4.2 via swiftly)
xcrun swift test --scratch-path .build/xcode-6.3   # same package on Xcode's Swift 6.3.2
swift run -c release OwnershipBenchmarks     # Ex 29/30 benchmarks (release only)
scripts/verify-compile-errors.sh             # every "this doesn't compile" claim, checked
scripts/diagnose-report.sh                   # Ex 20: @diagnose migration-debt report
```

## Layout

| Path | Contents |
| --- | --- |
| `Sources/Language/` | Ex 01–23, one file per exercise (`E01_ValueSemantics.swift` …) |
| `Sources/Payments`, `Pricing`, `Listing` | Ex 05: modules that collide on purpose |
| `Sources/LanguageMacros/`, `LanguageMacrosClient/` | Ex 23: macro implementation and declarations |
| `Sources/Migration/` | Ex 20: warnings-as-errors module with scoped `@diagnose` |
| `Sources/Ownership/` | Ex 24–30: noncopyable types, `InlineArray`/`Span`, `UniqueArray`/`UniqueBox` |
| `Sources/StayKit/` | Capstone: booking engine core |
| `Benchmarks/OwnershipBenchmarks/` | Release-mode benchmark harness |
| `CompileFailures/` | One snippet per compile error quoted in the notes |
| `scripts/compiler-bugs/` | Reproducers for the two Swift compiler bugs found during the exercises |
