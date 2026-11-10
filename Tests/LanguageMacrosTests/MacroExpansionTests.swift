// Ex 23 — Macro expansion tests (Swift Testing + SwiftSyntaxMacrosGenericTestSupport).

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import LanguageMacros

private let macros: [String: MacroSpec] = [
    "listingURL": MacroSpec(type: ListingURLMacro.self),
    "AddAsync": MacroSpec(type: AddAsyncMacro.self),
]

private func assertExpansion(
    _ source: String,
    expandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    assertMacroExpansion(
        source,
        expandedSource: expandedSource,
        diagnostics: diagnostics,
        macroSpecs: macros,
        indentationWidth: .spaces(4),
        failureHandler: { failure in
            Issue.record("\(failure.message)", sourceLocation: sourceLocation)
        }
    )
}

@Suite("Ex23 #listingURL")
struct ListingURLMacroTests {
    @Test func validURLExpands() {
        assertExpansion(
            #"let url = #listingURL("https://example.com/l/1")"#,
            expandedSource: #"let url = URL(string: "https://example.com/l/1")!"#
        )
    }

    @Test func invalidURLIsACompileError() {
        assertExpansion(
            #"let url = #listingURL("not a url")"#,
            expandedSource: #"let url = #listingURL("not a url")"#,
            diagnostics: [DiagnosticSpec(message: "'not a url' is not a valid absolute URL", line: 1, column: 23)]
        )
    }

    @Test func interpolationIsRejected() {
        assertExpansion(
            #"let url = #listingURL("https://\(host)")"#,
            expandedSource: #"let url = #listingURL("https://\(host)")"#,
            diagnostics: [DiagnosticSpec(message: "#listingURL requires a static string literal (no interpolation)", line: 1, column: 11)]
        )
    }

    @Test func httpGetsAFixIt() {
        assertExpansion(
            #"let url = #listingURL("http://example.com")"#,
            expandedSource: #"let url = URL(string: "http://example.com")!"#,
            diagnostics: [
                DiagnosticSpec(
                    message: "listing URLs must use https",
                    line: 1,
                    column: 23,
                    fixIts: [FixItSpec(message: "Replace 'http://' with 'https://'")]
                ),
            ]
        )
    }
}

@Suite("Ex23 @AddAsync")
struct AddAsyncMacroTests {
    @Test func generatesTypedAsyncPeer() {
        assertExpansion(
            """
            @AddAsync
            public func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void) {
            }
            """,
            expandedSource: """
            public func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void) {
            }

            public func fetchListing(id: ListingID) async throws(ListingError) -> Listing {
                let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Listing, ListingError>, Never>) in
                    fetchListing(id: id) { result in
                        continuation.resume(returning: result)
                    }
                }
                return try result.get()
            }
            """
        )
    }

    @Test func handlesUnlabeledAndNestedGenericTypes() {
        assertExpansion(
            """
            @AddAsync
            static func search(_ query: String, limit max: Int, completion: @escaping (Result<[String: [Int]], any Error>) -> Void) {
            }
            """,
            expandedSource: """
            static func search(_ query: String, limit max: Int, completion: @escaping (Result<[String: [Int]], any Error>) -> Void) {
            }

            static func search(_ query: String, limit max: Int) async throws(any Error) -> [String: [Int]] {
                let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<[String: [Int]], any Error>, Never>) in
                    search(query, limit: max) { result in
                        continuation.resume(returning: result)
                    }
                }
                return try result.get()
            }
            """
        )
    }

    @Test func rejectsNonFunctions() {
        assertExpansion(
            "@AddAsync var x = 1",
            expandedSource: "var x = 1",
            diagnostics: [DiagnosticSpec(message: "@AddAsync can only be applied to a function", line: 1, column: 1)]
        )
    }

    @Test func rejectsMissingCompletion() {
        assertExpansion(
            "@AddAsync func load(id: Int) {}",
            expandedSource: "func load(id: Int) {}",
            diagnostics: [DiagnosticSpec(message: "@AddAsync requires the last parameter to be named 'completion'", line: 1, column: 16)]
        )
    }

    @Test func rejectsNonResultCompletion() {
        assertExpansion(
            "@AddAsync func load(completion: @escaping (Int) -> Void) {}",
            expandedSource: "func load(completion: @escaping (Int) -> Void) {}",
            diagnostics: [DiagnosticSpec(message: "@AddAsync requires a completion of type '(Result<Success, Failure>) -> Void'", line: 1, column: 33)]
        )
    }

    @Test func parsesResultTypes() {
        #expect(AddAsyncMacro.parseResultCompletion("@escaping @Sendable (Result<A, B>) -> Void")! == ("A", "B"))
        #expect(AddAsyncMacro.parseResultCompletion("(Result<[K: V], E>) -> ()")! == ("[K: V]", "E"))
        #expect(AddAsyncMacro.parseResultCompletion("(Int) -> Void") == nil)
    }
}
