// Ex 11 — Associated types and primary associated types.

import Foundation

package enum E11 {
    /// `Entity` is the *primary* associated type: it's what callers constrain
    /// (`some Repository<Listing>`), just like `Element` in `Collection<Element>`.
    ///
    /// Design note (step 5): `Entity.ID` is NOT a separate primary associated
    /// type. It's fully determined by `Entity` (via `Identifiable`), so making it
    /// primary would only add a redundant, contradictory-capable parameter
    /// (`Repository<Listing, Int>` would be nonsense when `Listing.ID` is a
    /// `ListingID`). Primary associated types should be the independent knobs
    /// callers actually choose.
    package protocol Repository<Entity> {
        associatedtype Entity: Identifiable
        associatedtype Entities: Collection = [Entity] where Entities.Element == Entity

        func all() -> Entities
        func find(_ id: Entity.ID) -> Entity?
        mutating func upsert(_ entity: Entity)
    }

    /// Insertion-ordered, O(1) lookup.
    package struct InMemoryRepository<E: Identifiable>: Repository {
        private var order: [E.ID] = []
        private var byID: [E.ID: E] = [:]

        package init(_ entities: [E] = []) {
            for entity in entities { upsert(entity) }
        }

        package func all() -> [E] { order.compactMap { byID[$0] } }
        package func find(_ id: E.ID) -> E? { byID[id] }

        package mutating func upsert(_ entity: E) {
            if byID.updateValue(entity, forKey: entity.id) == nil {
                order.append(entity.id)
            }
        }
    }

    /// Kept sorted on every insert (binary search for the insertion point).
    package struct SortedRepository<E: Identifiable & Comparable>: Repository {
        private var storage: [E] = []

        package init(_ entities: [E] = []) {
            for entity in entities { upsert(entity) }
        }

        package func all() -> [E] { storage }
        package func find(_ id: E.ID) -> E? { storage.first { $0.id == id } }

        package mutating func upsert(_ entity: E) {
            storage.removeAll { $0.id == entity.id }
            var low = 0, high = storage.count
            while low < high {
                let mid = (low + high) / 2
                if storage[mid] < entity { low = mid + 1 } else { high = mid }
            }
            storage.insert(entity, at: low)
        }
    }

    /// Callers know `Entity == Listing`. They do NOT know `Entities` is an
    /// Array: they only get "some Collection of Listing".
    static func makeListingRepository(_ listings: [Listing] = []) -> some Repository<Listing> {
        InMemoryRepository(listings)
    }
}

extension E11.Repository {
    /// Works for every repository: group entities by any hashable key.
    func duplicates<Key: Hashable>(by keyPath: KeyPath<Entity, Key>) -> [Key: [Entity]] {
        Dictionary(grouping: all(), by: { $0[keyPath: keyPath] }).filter { $0.value.count > 1 }
    }
}

extension E11.Repository where Entity: Hashable {
    /// Only available when entities are hashable (constrained protocol extension).
    func entitySet() -> Set<Entity> { Set(all()) }
}

extension Listing: Comparable {
    /// Cheapest first, title as a tie-breaker, so the order is deterministic.
    package static func < (lhs: Listing, rhs: Listing) -> Bool {
        (lhs.nightlyPrice, lhs.title) < (rhs.nightlyPrice, rhs.title)
    }
}
