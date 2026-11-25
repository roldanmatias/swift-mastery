// The bridges between Combine and Swift concurrency, and the hand-written operators.

import Combine
import Concurrency
import Synchronization
import Testing
@testable import CombineSearch

@MainActor
@Suite("Combine ↔ async bridges")
struct BridgeTests {
    @Test("publisher.values turns a finite publisher into an AsyncSequence")
    func valuesOfFinitePublisher() async {
        var collected: [Int] = []
        for await value in [1, 2, 3].publisher.values { collected.append(value) }
        #expect(collected == [1, 2, 3])
    }

    @Test("stream(of:) subscribes immediately, so nothing sent before the loop starts is lost")
    func streamSubscribesEagerly() async {
        let subject = PassthroughSubject<Int, Never>()
        let values = stream(of: subject)          // subscribed *now*

        subject.send(1)
        subject.send(2)                           // no consumer yet
        subject.send(completion: .finished)

        var collected: [Int] = []
        for await value in values { collected.append(value) }
        #expect(collected == [1, 2])
    }

    @Test("dropping the last reference to the stream cancels the Combine subscription")
    func droppingStreamCancelsSubscription() async {
        let cancelled = Flag()
        let subject = PassthroughSubject<Int, Never>()

        // `break` alone does not end an AsyncStream: the stream is only terminated when the
        // consumer task is cancelled or the last reference to it is released. Scoping the
        // stream to a function makes the release explicit.
        func readFirstValue() async {
            let values = stream(of: subject.handleEvents(receiveCancel: { cancelled.set() }))
            subject.send(1)
            for await value in values {
                #expect(value == 1)
                break
            }
        }
        await readFirstValue()
        await cancelled.waitUntilSet()
        #expect(cancelled.isSet)
    }

    @Test("cancelling the consuming task cancels the Combine subscription")
    func cancellingConsumerCancelsSubscription() async {
        let cancelled = Flag()
        let subject = PassthroughSubject<Int, Never>()
        let values = stream(of: subject.handleEvents(receiveCancel: { cancelled.set() }))

        let consumer = Task { for await _ in values {} }
        consumer.cancel()
        await consumer.value
        await cancelled.waitUntilSet()
        #expect(cancelled.isSet)
    }

    @Test("taskPublisher emits one value and completes")
    func taskPublisherEmitsOnce() async {
        let publisher = taskPublisher { 42 }
        var collected: [Int] = []
        for await value in publisher.values { collected.append(value) }
        #expect(collected == [42])
    }

    @Test("cancelling a taskPublisher subscription cancels its Task")
    func taskPublisherCancelsTask() async {
        let started = AsyncGate()
        let cancelled = Flag()
        let finished = AsyncGate()
        let publisher = taskPublisher { @Sendable in
            await started.open()
            await suspendUntilCancelled()          // returns only when this Task is cancelled
            cancelled.set()
            await finished.open()
            return 0
        }
        let subscription = publisher.sink { _ in }
        await started.wait()
        subscription.cancel()
        await finished.wait()
        #expect(cancelled.isSet)
    }
}

@Suite("Hand-written AsyncSequence operators")
struct OperatorTests {
    @Test("debounced emits only after silence, and flushes the last element when upstream ends")
    func debounceFlushesAtEnd() async {
        let clock = CountingClock()
        let (source, input) = AsyncStream.makeStream(of: Int.self)
        let debounced = source.debounced(for: .milliseconds(300), clock: clock)
        let collector = Task { var all: [Int] = []; for await v in debounced { all.append(v) }; return all }

        input.yield(1)
        input.yield(2)
        input.finish()                               // upstream ends while 2 is still waiting
        await clock.waitForSleeps(2)                 // both timers started; 1's was cancelled by 2
        await clock.base.waitForSleepers(1)
        clock.base.advance(by: .milliseconds(300))
        #expect(await collector.value == [2])
    }

    @Test("removingDuplicates drops only consecutive repeats")
    func removesConsecutiveDuplicates() async {
        let (source, input) = AsyncStream.makeStream(of: Int.self)
        [1, 1, 2, 2, 1].forEach { input.yield($0) }
        input.finish()
        var collected: [Int] = []
        for await v in source.removingDuplicates() { collected.append(v) }
        #expect(collected == [1, 2, 1])
    }

    @Test("mapLatest drops the result of a superseded element")
    func mapLatestDropsStale() async {
        let slow = AsyncGate()
        let secondStarted = AsyncGate()
        let (source, input) = AsyncStream.makeStream(of: Int.self)
        let results = source.mapLatest { @Sendable (n: Int) -> Int in
            if n == 1 { await slow.wait() }          // element 1 is slow and ignores cancellation
            if n == 2 { await secondStarted.open() }
            return n * 10
        }
        let collector = Task { var all: [Int] = []; for await v in results { all.append(v) }; return all }

        input.yield(1)
        input.yield(2)                               // supersedes 1
        await secondStarted.wait()                   // the operator has consumed 2
        await slow.open()                            // 1 finishes late
        input.finish()
        #expect(await collector.value == [20])
    }
}
