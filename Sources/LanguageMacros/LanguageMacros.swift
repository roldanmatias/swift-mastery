// Ex 23 — Macro implementations. These run inside the compiler (as a separate,
// sandboxed plugin process) and only see the *syntax* of the code they're
// attached to, never its types.

import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct LanguageMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        ListingURLMacro.self,
        AddAsyncMacro.self,
    ]
}

// MARK: - Diagnostics

enum MacroDiagnostic: DiagnosticMessage {
    case notStaticString
    case invalidURL(String)
    case insecureScheme
    case notAFunction
    case missingCompletion
    case completionNotResult

    var message: String {
        switch self {
        case .notStaticString: "#listingURL requires a static string literal (no interpolation)"
        case .invalidURL(let text): "'\(text)' is not a valid absolute URL"
        case .insecureScheme: "listing URLs must use https"
        case .notAFunction: "@AddAsync can only be applied to a function"
        case .missingCompletion: "@AddAsync requires the last parameter to be named 'completion'"
        case .completionNotResult: "@AddAsync requires a completion of type '(Result<Success, Failure>) -> Void'"
        }
    }

    var diagnosticID: MessageID {
        let id: String = switch self {
        case .notStaticString: "notStaticString"
        case .invalidURL: "invalidURL"
        case .insecureScheme: "insecureScheme"
        case .notAFunction: "notAFunction"
        case .missingCompletion: "missingCompletion"
        case .completionNotResult: "completionNotResult"
        }
        return MessageID(domain: "LanguageMacros", id: id)
    }

    var severity: DiagnosticSeverity { .error }
}

struct UseHTTPSFixIt: FixItMessage {
    var message: String { "Replace 'http://' with 'https://'" }
    var fixItID: MessageID { MessageID(domain: "LanguageMacros", id: "useHTTPS") }
}

// MARK: - #listingURL("https://…") — freestanding expression macro

/// Validates the URL at compile time and expands to a non-optional `URL`.
struct ListingURLMacro: ExpressionMacro {
    static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard
            let argument = node.arguments.first?.expression,
            let literal = argument.as(StringLiteralExprSyntax.self),
            literal.segments.count == 1,
            case .stringSegment(let segment)? = literal.segments.first
        else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: node, message: MacroDiagnostic.notStaticString)])
        }

        let text = segment.content.text
        guard let url = URL(string: text), url.scheme != nil, url.host != nil else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: argument, message: MacroDiagnostic.invalidURL(text))])
        }

        if url.scheme == "http" {
            let fixed = "https://" + text.dropFirst("http://".count)
            context.diagnose(
                Diagnostic(
                    node: argument,
                    message: MacroDiagnostic.insecureScheme,
                    fixIt: FixIt(
                        message: UseHTTPSFixIt(),
                        changes: [.replace(oldNode: Syntax(literal), newNode: Syntax(StringLiteralExprSyntax(content: fixed)))]
                    )
                )
            )
        }

        // Safe force-unwrap: we just proved at compile time that it parses.
        return "URL(string: \(literal))!"
    }
}

// MARK: - @AddAsync — attached peer macro

/// Generates the `async throws(Failure)` twin of a completion-handler function:
///
///     @AddAsync
///     func fetchListing(id: ListingID, completion: @escaping @Sendable (Result<Listing, ListingError>) -> Void)
///
/// gets a peer:
///
///     func fetchListing(id: ListingID) async throws(ListingError) -> Listing
struct AddAsyncMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: node, message: MacroDiagnostic.notAFunction)])
        }

        let parameters = Array(function.signature.parameterClause.parameters)
        guard let completion = parameters.last, completion.firstName.text == "completion" else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: function.name, message: MacroDiagnostic.missingCompletion)])
        }

        guard let (success, failure) = parseResultCompletion(completion.type.trimmedDescription) else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: completion.type, message: MacroDiagnostic.completionNotResult)])
        }

        let kept = parameters.dropLast()
        let parameterList = kept
            .map { $0.with(\.trailingComma, nil).trimmedDescription }
            .joined(separator: ", ")
        let arguments = kept.map { parameter -> String in
            let label = parameter.firstName.text
            let name = (parameter.secondName ?? parameter.firstName).text
            return label == "_" ? name : "\(label): \(name)"
        }
        let callArguments = arguments.joined(separator: ", ")

        let modifiers = function.modifiers.isEmpty ? "" : function.modifiers.trimmedDescription + " "
        let generics = function.genericParameterClause?.trimmedDescription ?? ""
        let whereClause = function.genericWhereClause.map { " " + $0.trimmedDescription } ?? ""
        let name = function.name.text

        // Resume with a `Result` (never throws through the continuation), then
        // `get()` rethrows it with its precise type.
        let peer: DeclSyntax = """
            \(raw: modifiers)func \(raw: name)\(raw: generics)(\(raw: parameterList)) async throws(\(raw: failure)) -> \(raw: success)\(raw: whereClause) {
                let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<\(raw: success), \(raw: failure)>, Never>) in
                    \(raw: name)(\(raw: callArguments)) { result in
                        continuation.resume(returning: result)
                    }
                }
                return try result.get()
            }
            """
        return [peer]
    }

    /// Parses `@escaping @Sendable (Result<A, B>) -> Void` into `(A, B)`.
    /// Works on the type's text so it doesn't depend on swift-syntax's
    /// generic-argument API, which changed between releases.
    static func parseResultCompletion(_ type: String) -> (success: String, failure: String)? {
        var text = Substring(type)
        while text.hasPrefix("@") {
            guard let space = text.firstIndex(of: " ") else { return nil }
            text = text[text.index(after: space)...].drop(while: \.isWhitespace)
        }
        guard text.hasPrefix("(Result<"), text.hasSuffix("-> Void") || text.hasSuffix("-> ()") else { return nil }

        let inner = text.dropFirst("(Result<".count)
        var depth = 0
        var comma: Substring.Index?
        var close: Substring.Index?
        for index in inner.indices {
            switch inner[index] {
            case "<", "[", "(": depth += 1
            case ">" where depth == 0: close = index
            case ">", "]", ")": depth -= 1
            case "," where depth == 0 && comma == nil: comma = index
            default: break
            }
            if close != nil { break }
        }
        guard let comma, let close else { return nil }
        let success = inner[..<comma].trimmingCharacters(in: .whitespaces)
        let failure = inner[inner.index(after: comma)..<close].trimmingCharacters(in: .whitespaces)
        guard !success.isEmpty, !failure.isEmpty else { return nil }
        return (success, failure)
    }
}
