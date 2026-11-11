// expect: main actor-isolated conformance of 'ListingDTO' to 'Decodable' cannot be used in @concurrent context
// flags: -swift-version 6 -default-isolation MainActor -enable-upcoming-feature InferIsolatedConformances
import Foundation
struct ListingDTO: Decodable { let id: Int }      // forgot `nonisolated`: the conformance is @MainActor
nonisolated enum ListingDecoder {
    @concurrent static func decode(_ data: Data) async throws -> Int {
        try JSONDecoder().decode(ListingDTO.self, from: data).id
    }
}
