// Tests for Ex 24–30 (ownership and performance).

import Foundation
@testable import Language
import Synchronization
import Testing
@testable import Ownership

/// Tests run in parallel and share `LockRegistry.shared`, so every test uses
/// fresh listing IDs.
enum TestIDs {
    private static let counter = Atomic<Int>(10_000)
    static func next() -> Int { counter.add(1, ordering: .relaxed).newValue }
}

private var registry: LockRegistry { .shared }

@Suite("Ex24 ReservationLock")
struct E24Tests {
    @Test func droppingALockReleasesIt() throws {
        let id = TestIDs.next()
        do {
            let lock = try ReservationLock(acquiring: id)
            #expect(registry.isHeld(lock.listingID))
        }   // `lock` is destroyed here: deterministic, end of scope
        #expect(!registry.isHeld(id))
        #expect(registry.receipts(for: id).map(\.wasForced) == [true])
    }

    @Test func releaseReleasesExactlyOnce() throws {
        let id = TestIDs.next()
        let lock = try ReservationLock(acquiring: id)
        let receipt = lock.release()   // consumes `lock`; `discard self` skips deinit
        #expect(receipt.wasForced == false)
        #expect(!registry.isHeld(id))
        #expect(registry.receipts(for: id).count == 1)
    }

    @Test func secondAcquireThrows() throws {
        let id = TestIDs.next()
        let first = try ReservationLock(acquiring: id)
        #expect(throws: LockError.alreadyHeld(listingID: id)) {
            _ = try ReservationLock(acquiring: id)
        }
        _ = first.release()
        let again = try ReservationLock(acquiring: id)   // free again
        _ = again.release()
    }
}

@Suite("Ex25 borrowing / consuming / inout")
struct E25Tests {
    @Test func threeConventions() throws {
        let id = TestIDs.next()
        var lock = try ReservationLock(acquiring: id)
        let before = lock.token

        #expect(E25.inspect(lock).contains("listing \(id)"))   // borrowed: still ours
        E25.renew(&lock)                                       // inout: mutated in place
        #expect(lock.token != before)
        #expect(registry.isHeld(id))

        let handoff = E25.transfer(lock, to: "front desk")     // consumed: `lock` is gone
        #expect(handoff.recipient == "front desk")
        #expect(handoff.lock.listingID == id)
    }

    @Test func consumeAvoidsTheCopy() {
        let calendar = AvailabilityCalendar(price: 100)
        let id = calendar._storageID
        let updated = E25.appendingBlock(consume calendar)    // reference moves in, stays unique
        #expect(updated._storageID == id)
        #expect(updated.availableDays == 364)
    }

    @Test func withoutConsumeACopyHappens() {
        let calendar = AvailabilityCalendar(price: 100)
        let updated = E25.appendingBlock(calendar)
        #expect(calendar.availableDays == 365)                // still used → had to copy
        #expect(updated._storageID != calendar._storageID)
    }

    @Test func explicitCopyOfABorrowedParameter() {
        let calendar = AvailabilityCalendar(price: 100)
        let copy = E25.duplicate(calendar)
        #expect(copy == calendar)
        #expect(copy._storageID == calendar._storageID)       // `copy` is a retain, CoW still applies
    }

    @Test func partialConsumption() throws {
        let id = TestIDs.next()
        let hold = E25.Hold(lock: try ReservationLock(acquiring: id), note: "VIP")
        let lock = hold.takeLock()                            // moves one field out; `note` is destroyed
        #expect(lock.release().listingID == id)
    }
}

@Suite("Ex26 Typestate")
struct E26Tests {
    func draft() -> DraftInfo { DraftInfo(listingID: TestIDs.next(), guest: "Matías", nights: 3) }

    @Test func enumHappyPath() {
        let info = draft()
        let draft = E26.Reservation.draft(info)
        #expect(draft.status == "draft")

        let confirmed = draft.confirm(payment: PaymentToken("tok_ok"))
        #expect(confirmed.rejectReason == nil)
        let reservation = confirmed.reservation()
        #expect(reservation.status == "confirmed")
        #expect(registry.isHeld(info.listingID))              // the lock moved into .confirmed

        let cancelled = reservation.cancel(reason: "plans changed").reservation()
        #expect(cancelled.status == "cancelled")
        #expect(!registry.isHeld(info.listingID))             // released on cancel
    }

    @Test func rejectedTransitionReturnsTheReservation() {
        let declined = E26.Reservation.draft(draft()).confirm(payment: PaymentToken("declined"))
        #expect(declined.rejectReason == .paymentDeclined)
        let stillDraft = declined.reservation()               // usable again
        #expect(stillDraft.status == "draft")
        let retried = stillDraft.confirm(payment: PaymentToken("tok_ok"))
        #expect(retried.rejectReason == nil)
    }

    @Test func invalidTransitions() {
        let cancelled = E26.Reservation.draft(draft()).cancel(reason: "x").reservation()
        let again = cancelled.cancel(reason: "y")
        #expect(again.rejectReason == .invalidTransition(from: "cancelled", action: "cancel"))
    }

    @Test func typestateStructs() throws {
        let info = draft()
        let confirmed = try E26.DraftReservation(info).confirm(payment: PaymentToken("tok_ok"))
        #expect(registry.isHeld(info.listingID))
        let cancelled = confirmed.cancel(reason: "storm")
        #expect(cancelled.receipt.listingID == info.listingID)
        #expect(!registry.isHeld(info.listingID))
    }

    @Test func typestateErrorCarriesTheDraftData() {
        let info = draft()
        #expect(throws: E26.ConfirmError(reason: .paymentDeclined, draft: info)) {
            _ = try E26.DraftReservation(info).confirm(payment: PaymentToken("declined"))
        }
    }
}

@Suite("Ex27 Noncopyable generics")
struct E27Tests {
    @Test func copyableBoxIsCopyable() {
        let a = E27.Box(1)
        var b = a                                             // a real copy: Box<Int> is Copyable
        b.value += 1
        #expect(a.value == 1)
        #expect(b.value == 2)
        #expect(a.peek() == 1)                                // Copyable-only extension
    }

    @Test func noncopyableBoxMoves() throws {
        let id = TestIDs.next()
        let box = E27.Box(try ReservationLock(acquiring: id))
        #expect(box.withValue { $0.listingID } == id)
        let mapped = box.map { lock in lock.release() }       // consumes the lock
        #expect(mapped.value.listingID == id)
        #expect(registry.receipts(for: id).count == 1)        // released exactly once
    }

    @Test func resourceProtocol() throws {
        let id = TestIDs.next()
        let receipt = ResourceOps.close(try ReservationLock(acquiring: id))
        #expect(receipt.listingID == id && !receipt.wasForced)
    }

    @Test func takeLeavesNil() throws {
        let id = TestIDs.next()
        var slot = E27.LockSlot(try ReservationLock(acquiring: id))
        let lock = slot.takeLock()
        let slotIsEmpty = slot.lock == nil, gotLock = lock != nil   // #expect can't take noncopyable operands
        #expect(slotIsEmpty)
        #expect(gotLock)
        #expect(registry.isHeld(id))
    }
}

#if compiler(>=6.4)
@Suite("Ex28 Noncopyable Equatable / Hashable (Swift 6.4)")
struct E28Tests {
    @Test func synthesizedConformances() {
        let a = SecretToken([1, 2, 3])
        let b = SecretToken([1, 2, 3])
        let c = SecretToken([9])
        // `#expect(a == b)` doesn't compile for noncopyable operands: the macro
        // copies operands to print them. Evaluate first, then expect the Bool.
        let equal = a == b, different = a != c
        #expect(equal)
        #expect(different)
        #expect(E28.hashOf(a) == E28.hashOf(b))
        #expect(a.redacted == "SecretToken(3 bytes, ••••)")
    }

    @Test func handWrittenConformances() {
        let a = APIKey(key: "k", scope: "READ")
        let b = APIKey(key: "k", scope: "read")
        let equal = a == b
        #expect(equal)
        #expect(E28.hashOf(a) == E28.hashOf(b))               // a == b ⇒ equal hashes
    }

    @Test func optionalComparesWithNil() {
        let missing: SecretToken? = nil
        let present: SecretToken? = SecretToken([1])
        let isMissing = missing == nil, isPresent = present != nil
        #expect(isMissing)
        #expect(isPresent)
    }

    @Test func conditionalConformanceOnBox() {
        let equal = E27.Box(SecretToken([1])) == E27.Box(SecretToken([1]))
        #expect(equal)
        #expect(E28.hashOf(E27.Box(SecretToken([1]))) == E28.hashOf(E27.Box(SecretToken([1]))))
    }

    @Test func comparableLocks() throws {
        let first = try ReservationLock(acquiring: TestIDs.next())
        let second = try ReservationLock(acquiring: TestIDs.next())
        let ordered = first < second
        #expect(ordered)
        #expect(E28.earliest(second, first) == first.token)
    }
}
#endif

@Suite("Ex29 InlineArray and Span")
struct E29Tests {
    @Test func bothImplementationsAgree() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let prices = (0..<Int.random(in: 7...400, using: &generator)).map { _ in Double.random(in: 50...500, using: &generator) }
            let expected = E29.weeklyAveragesBaseline(prices)
            #expect(E29.weeklyAveragesInline(prices) == expected)
            #expect(E29.weeklyAveragesReusedArray(prices) == expected)
        }
        #expect(E29.weeklyAveragesInline([1, 2, 3]).isEmpty)
    }

    @Test func spanIsStorageAgnostic() {
        let array: [Double] = [1, 2, 3, 4]
        var inline: [4 of Double] = .init(repeating: 0)
        for i in inline.indices { inline[i] = array[i] }
        #expect(E29.average(array.span) == 2.5)
        #expect(E29.average(inline.span) == 2.5)
    }

    @Test func mutableSpanNormalizesInPlace() {
        var prices: [Double] = [50, 100, 200]
        E29.normalize(&prices)
        #expect(prices == [0.25, 0.5, 1])
    }

    @Test func layoutAndEagerCopy() {
        #expect(MemoryLayout<InlineArray<7, Double>>.size == 56)   // 7 × 8 bytes, inline
        #expect(MemoryLayout<[Double]>.size == 8)                   // just a buffer reference
        let a: [3 of Int] = [1, 2, 3]
        var b = a                                                   // copies all 3 elements now
        b[0] = 9
        #expect(a[0] == 1 && b[0] == 9)
    }
}

#if compiler(>=6.4)
@Suite("Ex30 UniqueArray / UniqueBox (Swift 6.4, macOS 27+)")
struct E30Tests {
    @available(macOS 27, iOS 27, *)
    @Test func lockPool() throws {
        let ids = (0..<3).map { _ in TestIDs.next() }
        var pool = LockPool()
        for id in ids { try pool.acquire(id) }
        #expect(pool.count == 3)
        #expect(pool.first.listingID == ids[0])
        #expect(pool.listingIDs() == ids)
        #expect(pool.release(listingID: ids[1])?.listingID == ids[1])
        let receipts = pool.releaseAll()
        #expect(Set(receipts.map(\.listingID)) == [ids[0], ids[2]])
        #expect(ids.allSatisfy { !registry.isHeld($0) })
    }

    @available(macOS 27, iOS 27, *)
    @Test func holdQueueBackpressure() throws {
        var queue = HoldQueue(capacity: 1)
        let accepted = queue.offer(try ReservationLock(acquiring: TestIDs.next())) == nil
        #expect(accepted)
        let rejected = queue.offer(try ReservationLock(acquiring: TestIDs.next()))
        let handedBack = rejected != nil                      // handed back, no trap
        #expect(handedBack)
        #expect(queue.count == 1)
    }

    #if DEBUG   // see the optimizer-crash note in E30_OwningContainers.swift
    @available(macOS 27, iOS 27, *)
    @Test func stackIsLIFOAndDropsIteratively() {
        var stack = NoncopyableStack<Int>()
        for i in 0..<3 { stack.push(i) }
        #expect(stack.pop() == 2)
        #expect(stack.pop() == 1)

        var big = NoncopyableStack<Int>()
        for i in 0..<1_000_000 { big.push(i) }                // dropped at end of scope, no stack overflow
        let hasElements = !big.isEmpty
        #expect(hasElements)
    }
    #endif

    @available(macOS 27, iOS 27, *)
    @Test func ownedSlotMutatesInPlace() throws {
        var slot = OwnedSlot(try ReservationLock(acquiring: TestIDs.next()))
        let before = slot.value.token
        slot.value.rotateToken()                              // through the `mutate` accessor
        #expect(slot.value.token != before)
        _ = slot.take().release()
    }

    @available(macOS 27, iOS 27, *)
    @Test func uniqueArraySpan() {
        var values = UniqueArray<Double>()
        for v in [1.0, 2.0, 3.0] { values.append(v) }
        #expect(E29.average(values.span) == 2)
    }
}
#endif
