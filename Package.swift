// swift-tools-version: 6.2
// Day 4 — Swift 6.4 language core. See notes/swift-6.4-language-exercises.md.
//
// Toolchain: this repo is pinned to Swift 6.4.2 via `.swift-version` (swiftly).
// Swift-6.4-only code is wrapped in `#if compiler(>=6.4)`, so the package also
// builds with Xcode 26.5 (Swift 6.3); the 6.4 exercises are simply skipped there.

import CompilerPluginSupport
import PackageDescription

// Ex 20 / Capstone C13: warnings-as-errors with scoped `@diagnose` escapes.
// Only enabled on 6.4, because `@diagnose` (SE-0522) does not exist on 6.3.
#if compiler(>=6.4)
let warningsAsErrors: [SwiftSetting] = [.treatAllWarnings(as: .error)]
#else
let warningsAsErrors: [SwiftSetting] = []
#endif

let package = Package(
    name: "swift-mastery",
    platforms: [.macOS(.v26), .iOS(.v26)],
    // No library products: nothing here is `public`. Cross-module APIs use
    // `package` access (visible to every target in this package, nobody else),
    // and tests use `@testable import`.
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"700.0.0"),
    ],
    targets: [
        // Ex 05 — three modules that collide on purpose (module selectors).
        .target(name: "Payments"),
        .target(name: "Pricing"),
        .target(name: "Listing"),

        // Ex 23 — macros.
        .macro(
            name: "LanguageMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "LanguageMacrosClient", dependencies: ["LanguageMacros"]),

        // Ex 01–23 (one file per exercise).
        .target(
            name: "Language",
            dependencies: ["Payments", "Pricing", "Listing", "LanguageMacrosClient"]
        ),

        // Ex 20 — a warnings-as-errors module that must keep calling a deprecated API.
        .target(name: "Migration", dependencies: ["Language"], swiftSettings: warningsAsErrors),

        // Ex 24–30 — ownership, noncopyable types, InlineArray/Span, UniqueArray/UniqueBox.
        .target(name: "Ownership", dependencies: ["Language"]),

        // Capstone.
        .target(
            name: "StayKit",
            dependencies: ["Language", "Ownership", "LanguageMacrosClient"],
            swiftSettings: warningsAsErrors
        ),

        // Ex 29–30 benchmarks: `swift run -c release OwnershipBenchmarks`
        .executableTarget(
            name: "OwnershipBenchmarks",
            dependencies: ["Ownership", "Language"],
            path: "Benchmarks/OwnershipBenchmarks"
        ),

        .testTarget(name: "LanguageTests", dependencies: ["Language", "Migration", "Payments", "Pricing"]),
        .testTarget(
            name: "LanguageMacrosTests",
            dependencies: [
                "LanguageMacros",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
            ]
        ),
        .testTarget(name: "OwnershipTests", dependencies: ["Ownership", "Language"]),
        .testTarget(name: "StayKitTests", dependencies: ["StayKit", "Language", "Ownership"]),
    ],
    swiftLanguageModes: [.v6]
)
