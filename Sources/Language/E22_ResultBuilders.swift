// Ex 22 — Result builders: a search-query DSL.

import Foundation

package enum E22 {
    package enum DateSpec: Equatable, Sendable {
        case exact(Date, Date)
        case flexible(weeks: Int)
    }

    package enum QueryComponent: Equatable, Sendable {
        case destination(String)
        case guests(Int)
        case petsAllowed
        case dates(DateSpec)
        case amenity(String)
        case keyword(String)
        case glassPreview
    }

    package protocol QueryConvertible {
        var component: QueryComponent { get }
    }

    package struct Destination: QueryConvertible {
        package let name: String
        package init(_ name: String) { self.name = name }
        package var component: QueryComponent { .destination(name) }
    }

    package struct Guests: QueryConvertible {
        package let count: Int
        package init(_ count: Int) { self.count = count }
        package var component: QueryComponent { .guests(count) }
    }

    package struct PetsAllowed: QueryConvertible {
        package init() {}
        package var component: QueryComponent { .petsAllowed }
    }

    package struct DateRange: QueryConvertible {
        package let spec: DateSpec
        package init(_ checkIn: Date, _ checkOut: Date) { spec = .exact(checkIn, checkOut) }
        private init(spec: DateSpec) { self.spec = spec }
        package static func flexible(weeks: Int) -> DateRange { DateRange(spec: .flexible(weeks: weeks)) }
        package var component: QueryComponent { .dates(spec) }
    }

    package struct Amenity: QueryConvertible {
        package let name: String
        package init(_ name: String) { self.name = name }
        package var component: QueryComponent { .amenity(name) }
    }

    package struct GlassPreview: QueryConvertible {
        package init() {}
        package var component: QueryComponent { .glassPreview }
    }

    package enum QueryIssue: Equatable, Sendable {
        case missingDestination
        case multipleDestinations(Int)
        case invalidGuests(Int)
    }

    package struct SearchQuery: Equatable, Sendable {
        package let components: [QueryComponent]
        package let issues: [QueryIssue]
        package var isValid: Bool { issues.isEmpty }

        package init(@SearchQueryBuilder _ build: () -> SearchQuery) {
            self = build()
        }

        package init(validating components: [QueryComponent]) {
            self.components = components
            var issues: [QueryIssue] = []
            let destinations = components.filter { if case .destination = $0 { true } else { false } }.count
            if destinations == 0 { issues.append(.missingDestination) }
            if destinations > 1 { issues.append(.multipleDestinations(destinations)) }
            for case .guests(let count) in components where !(1...16).contains(count) {
                issues.append(.invalidGuests(count))
            }
            self.issues = issues
        }

        package var destination: String? {
            for case .destination(let name) in components { return name }
            return nil
        }

        package var keywords: [String] {
            components.compactMap { if case .keyword(let k) = $0 { k } else { nil } }
        }
    }

    /// The compiler rewrites the closure body into calls to these methods.
    /// Partial result type: `[QueryComponent]`. Final type: `SearchQuery`.
    @resultBuilder
    package enum SearchQueryBuilder {
        // Each statement → partial result
        package static func buildExpression(_ component: some QueryConvertible) -> [QueryComponent] {
            [component.component]
        }

        /// Plain strings become keyword filters.
        package static func buildExpression(_ keyword: String) -> [QueryComponent] {
            [.keyword(keyword)]
        }

        // Combining statements, pairwise (SE-0348): no 10-argument limit.
        package static func buildPartialBlock(first: [QueryComponent]) -> [QueryComponent] { first }

        package static func buildPartialBlock(accumulated: [QueryComponent], next: [QueryComponent]) -> [QueryComponent] {
            accumulated + next
        }

        /// Empty body `{ }`.
        package static func buildBlock() -> [QueryComponent] { [] }

        // `if` without `else`
        package static func buildOptional(_ component: [QueryComponent]?) -> [QueryComponent] {
            component ?? []
        }

        // `if/else` and `switch`
        package static func buildEither(first component: [QueryComponent]) -> [QueryComponent] { component }
        package static func buildEither(second component: [QueryComponent]) -> [QueryComponent] { component }

        // `for … in`
        package static func buildArray(_ components: [[QueryComponent]]) -> [QueryComponent] {
            components.flatMap { $0 }
        }

        // `if #available(…)`: erases availability-gated types (SwiftUI needs
        // this because its partial results are typed per branch).
        package static func buildLimitedAvailability(_ component: [QueryComponent]) -> [QueryComponent] {
            component
        }

        // Final validation/packaging.
        package static func buildFinalResult(_ components: [QueryComponent]) -> SearchQuery {
            SearchQuery(validating: components)
        }
    }

    // What the compiler generates for (whiteboard answer):
    //
    //     SearchQuery {
    //         Destination("BA")
    //         if flexible { DateRange.flexible(weeks: 2) } else { DateRange(a, b) }
    //     }
    //
    // becomes roughly:
    //
    //     let v0 = SearchQueryBuilder.buildExpression(Destination("BA"))
    //     let v1: [QueryComponent]
    //     if flexible {
    //         v1 = SearchQueryBuilder.buildEither(first: SearchQueryBuilder.buildExpression(DateRange.flexible(weeks: 2)))
    //     } else {
    //         v1 = SearchQueryBuilder.buildEither(second: SearchQueryBuilder.buildExpression(DateRange(a, b)))
    //     }
    //     let p0 = SearchQueryBuilder.buildPartialBlock(first: v0)
    //     let p1 = SearchQueryBuilder.buildPartialBlock(accumulated: p0, next: v1)
    //     return SearchQueryBuilder.buildFinalResult(p1)
}
