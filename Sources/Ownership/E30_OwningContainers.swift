// Ex 30 — `UniqueArray` and `UniqueBox`: owning containers (SE-0517, SE-0527).
//
// Findings on Swift 6.4.2:
// - `UniqueArray` and `UniqueBox` ship in the STANDARD LIBRARY (there's no
//   `Containers` module), availability-gated to macOS 27 / iOS 27.
//   This code compiles for macOS 26 behind `@available(macOS 27, iOS 27, *)`;
//   the tests run on macOS 27+ and are skipped on macOS 26.
// - `RigidArray` is NOT in the 6.4.2 standard library, so `HoldQueue` below
//   implements the same fixed-capacity, push-returns-the-rejected-element
//   behavior on top of `UniqueArray(capacity:)`.
// - `deinit` can't mutate `self` yet (SE-0544 is accepted, not implemented), so
//   `LockList` gets its iterative drop from a private class's `deinit`.

#if compiler(>=6.4)

@available(macOS 27, iOS 27, *)
package struct LockPool: ~Copyable {
    private var locks = UniqueArray<ReservationLock>()

    package init() {}

    package var count: Int { locks.count }

    package mutating func acquire(_ listingID: Int) throws(LockError) {
        locks.append(try ReservationLock(acquiring: listingID))
    }

    /// `remove(at:)` moves the lock out of the array; `release()` consumes it.
    package mutating func release(listingID: Int) -> ReleaseReceipt? {
        for index in locks.indices where locks[index].listingID == listingID {
            return locks.remove(at: index).release()
        }
        return nil
    }

    /// Drains the pool. `consuming`: the pool is gone afterwards.
    package consuming func releaseAll() -> [ReleaseReceipt] {
        var receipts: [ReleaseReceipt] = []
        while let lock = locks.popLast() {
            receipts.append(lock.release())
        }
        return receipts
    }

    /// Borrow accessor (SE-0507): returns a borrow of existing storage instead
    /// of producing a new value (`get`), so it works for noncopyable values and
    /// never copies. (See `OwnedSlot` below for `mutate`.)
    package var first: ReservationLock {
        borrow { return locks[0] }
    }

    /// Borrowing iteration (SE-0516 `Iterable`): `for lock in locks` borrows
    /// each element, no copies.
    package func listingIDs() -> [Int] {
        var ids: [Int] = []
        for lock in locks { ids.append(lock.listingID) }
        return ids
    }
}

/// Borrow + mutate accessors forwarding through `UniqueBox.value` (itself a
/// borrow/mutate property). `mutate` returns exclusive in-place access instead
/// of `get`/`set`'s copy-out / modify / write-back.
///
/// Rules found on Swift 6.4.2 (full compile, these are SIL-level checks):
/// - `mutate { return &storedProperty }` ✅ and `&box.value` ✅
/// - `mutate { return &uniqueArray[0] }` ❌ "error: invalid return value from a
///   mutate accessor" (the array subscript isn't a returnable mutate path yet;
///   `borrow { return uniqueArray[0] }` is fine)
/// - `yielding mutate` ❌ "'yielding mutate' accessor is only valid when
///   experimental feature coroutine accessors is enabled"
/// - a `borrow` accessor needs a `mutate` (not `_modify`/`set`) partner if the
///   property is mutable: "A 'borrow' accessor can only be defined along with
///   a 'mutate' accessor"
@available(macOS 27, iOS 27, *)
struct OwnedSlot<Element: ~Copyable>: ~Copyable {
    private var storage: UniqueBox<Element>

    init(_ element: consuming Element) {
        storage = UniqueBox(element)
    }

    var value: Element {
        borrow { return storage.value }
        mutate { return &storage.value }
    }

    consuming func take() -> Element {
        storage.consume()
    }
}

/// Fixed-capacity queue with backpressure: never grows, never traps.
@available(macOS 27, iOS 27, *)
struct HoldQueue: ~Copyable {
    private var holds: UniqueArray<ReservationLock>
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        holds = UniqueArray(capacity: capacity)
    }

    var count: Int { holds.count }

    /// Returns `nil` when accepted, or hands the lock back when full
    /// (the `RigidArray.pushLast` contract).
    mutating func offer(_ lock: consuming ReservationLock) -> ReservationLock? {
        guard holds.count < capacity else { return lock }
        holds.append(lock)
        return nil
    }
}

// `#if DEBUG`: Swift 6.4.2's optimizer CRASHES on any recursive noncopyable
// type linked through `UniqueBox` (repro:
// scripts/compiler-bugs/recursive-uniquebox-optimizer-crash.swift). It's
// correct code and works at -Onone, so it's compiled in debug builds (where
// the tests run) until a fixed compiler ships.
#if DEBUG

/// A singly linked stack of noncopyable values, using `UniqueBox` for the
/// recursive link (a noncopyable enum can't be `indirect`).
@available(macOS 27, iOS 27, *)
struct NoncopyableStack<Element: ~Copyable>: ~Copyable {
    struct Node: ~Copyable {
        var element: Element
        var next: UniqueBox<Node>?
    }

    /// Owns the chain. Its `deinit` CAN mutate its own stored property, so it
    /// drops nodes one by one. With the default recursive destruction, each
    /// node's destructor would destroy the next: 1M nodes = 1M stack frames.
    private final class Chain {
        var head: UniqueBox<Node>?
        deinit {
            var current = head.take()
            while let box = current.take() {
                current = box.consume().next   // node destroyed here, one at a time
            }
        }
    }

    // A noncopyable struct never shares this reference, so it's effectively unique.
    private let chain = Chain()

    var isEmpty: Bool { chain.head == nil }

    mutating func push(_ element: consuming Element) {
        chain.head = UniqueBox(Node(element: element, next: chain.head.take()))
    }

    mutating func pop() -> Element? {
        guard let box = chain.head.take() else { return nil }
        let node = box.consume()
        chain.head = node.next
        return node.element
    }
}

@available(macOS 27, iOS 27, *)
typealias LockList = NoncopyableStack<ReservationLock>

#endif // DEBUG

#endif
