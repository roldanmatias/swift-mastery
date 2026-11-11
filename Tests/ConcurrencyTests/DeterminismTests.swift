// Tests for C17–C20 (clocks, task context, cleanup, bounded groups).

import Testing
@testable import Concurrency

@Suite("C17 Injected clocks")
struct C17Tests {
    struct Flaky: Error {}

    @Test func backoffDelays() {
        let backoff = Backoff(initialDelay: .milliseconds(100), maxAttempts: 4)
        #expect((1...3).map(backoff.delay(beforeRetry:)) == [.milliseconds(100), .milliseconds(200), .milliseconds(400)])
    }

    @Test func retriesOnlyWhenTimeMoves() async throws {
        let clock = ManualClock()
        let attempts = Counter()
        let task = Task {
            try await retrying(Backoff(initialDelay: .milliseconds(100), maxAttempts: 4), clock: clock) {
                if attempts.increment() < 3 { throw Flaky() }
                return "ok"
            }
        }
        await clock.waitForSleepers(1)
        #expect(attempts.current == 1)

        clock.advance(by: .milliseconds(100))
        await clock.waitForSleepers(1)              // second attempt failed, now waiting 200 ms
        #expect(attempts.current == 2)

        clock.advance(by: .milliseconds(200))
        #expect(try await task.value == "ok")
        #expect(attempts.current == 3)
        #expect(clock.now.offset == .milliseconds(300))
    }

    @Test func givesUpAfterMaxAttempts() async {
        let clock = ManualClock()
        let task = Task {
            try await retrying(Backoff(initialDelay: .seconds(1), maxAttempts: 2), clock: clock) { () throws -> Int in throw Flaky() }
        }
        await clock.waitForSleepers(1)
        clock.advance(by: .seconds(1))
        await #expect(throws: Flaky.self) { try await task.value }
    }

    @Test func cancellingDuringBackoffStopsImmediately() async {
        let clock = ManualClock()
        let attempts = Counter()
        let task = Task {
            try await retrying(Backoff(initialDelay: .seconds(60), maxAttempts: 5), clock: clock) { () throws -> Int in
                attempts.increment()
                throw Flaky()
            }
        }
        await clock.waitForSleepers(1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(attempts.current == 1)
    }

    @Test func timeoutFiresWhenTheClockPassesTheDeadline() async {
        let clock = ManualClock()
        let task = Task {
            try await withTimeout(.seconds(5), clock: clock) { await suspendUntilCancelled(); return 1 }
        }
        await clock.waitForSleepers(1)
        clock.advance(by: .seconds(5))
        await #expect(throws: TimeoutError.self) { try await task.value }
    }

    @Test func fastOperationsBeatTheTimeout() async throws {
        let clock = ManualClock()
        #expect(try await withTimeout(.seconds(5), clock: clock) { 42 } == 42)   // timer task is cancelled
    }
}

@Suite("C18 Task locals and priority")
struct C18Tests {
    @Test func taskLocalsFlowToChildrenButNotDetachedTasks() async {
        let observed = await observeTaskLocalPropagation()
        #expect(observed == .init(asyncLet: "req-42", groupChild: "req-42", unstructured: "req-42", detached: nil))
    }

    @Test func taskLocalsAreScoped() async {
        #expect(logLine("search") == "[-] search")
        RequestContext.$requestID.withValue("req-1") {
            #expect(logLine("search") == "[req-1] search")
        }
        #expect(RequestContext.requestID == nil)
    }

    @Test func priorityEscalationIsObservable() async {
        let prefetch = Prefetch()
        let task = prefetch.start()
        await prefetch.waitUntilStarted()

        task.escalatePriority(to: .high)
        prefetch.finish()

        #expect(await task.value >= .high)
        #expect(prefetch.observedEscalations.contains(.high))
    }
}

@Suite("C19 Async cleanup")
struct C19Tests {
    struct Failed: Error {}

    @Test func cleanupRunsAfterSuccessAndFailure() async throws {
        let lease = SyncLease()
        #expect(try await withAsyncCleanup({ 1 }, cleanup: { await lease.release() }) == 1)
        #expect(await lease.released)

        let other = SyncLease()
        await #expect(throws: Failed.self) {
            try await withAsyncCleanup({ () throws -> Int in throw Failed() }, cleanup: { await other.release() })
        }
        #expect(await other.released)
    }

    @Test func cleanupIsShieldedFromCancellation() async {
        let lease = SyncLease()
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            try await withAsyncCleanup({
                startedContinuation.yield()
                await suspendUntilCancelled()
                try Task.checkCancellation()
                return 1
            }, cleanup: { await lease.release() })
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await lease.released)
        #expect(await lease.releaseSawCancellation == false)   // shielded
    }

    #if compiler(>=6.4)
    @Test func awaitInDeferRunsCleanupButInsideTheCancelledTask() async {
        let lease = SyncLease()
        await #expect(throws: CancellationError.self) {
            try await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await syncReleasingInDefer(lease) { try Task.checkCancellation() }
            }.value
        }
        #expect(await lease.released)
        #expect(await lease.releaseSawCancellation == true)    // the cleanup is cancelled too
    }

    @Test func shieldedDeferLetsCleanupFinish() async {
        let lease = SyncLease()
        await #expect(throws: CancellationError.self) {
            try await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await syncReleasingInShieldedDefer(lease) { try Task.checkCancellation() }
            }.value
        }
        #expect(await lease.releaseSawCancellation == false)
    }
    #endif

    @Test func unshieldedCleanupSeesCancellation() async {
        let lease = SyncLease()
        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await lease.release()             // what `defer`-style cleanup would observe
        }.value
        #expect(await lease.releaseSawCancellation == true)
    }
}

@Suite("C20 Bounded and discarding task groups")
struct C20Tests {
    @Test(arguments: [1, 3, 8])
    func uploadsStayWithinTheLimitAndKeepOrder(limit: Int) async throws {
        let gauge = ConcurrencyGauge()
        let photos = (0..<20).map { "photo-\($0)" }
        let urls = try await PhotoUploader.uploadAll(photos, maxConcurrent: limit) { photo in
            gauge.enter()
            defer { gauge.leave() }
            await Task.yield()
            return "cdn/\(photo)"
        }
        #expect(urls == photos.map { "cdn/\($0)" })
        #expect(gauge.peak <= limit)
    }

    @Test func aFailedUploadFailsTheBatch() async {
        struct UploadFailed: Error {}
        await #expect(throws: UploadFailed.self) {
            try await PhotoUploader.uploadAll(["a", "b", "c"], maxConcurrent: 2) { photo in
                if photo == "b" { throw UploadFailed() }
                return photo
            }
        }
    }

    @Test func discardingGroupProcessesAnEventStream() async throws {
        let handled = Counter()
        let (events, continuation) = AsyncStream.makeStream(of: Int.self)
        for event in 0..<100 { continuation.yield(event) }
        continuation.finish()

        try await WebhookProcessor.process(events) { _ in handled.increment() }
        #expect(handled.current == 100)
    }

    @Test func discardingGroupRethrowsTheFirstError() async {
        struct BadEvent: Error {}
        let (events, continuation) = AsyncStream.makeStream(of: Int.self)
        for event in 0..<10 { continuation.yield(event) }
        continuation.finish()

        await #expect(throws: BadEvent.self) {
            try await WebhookProcessor.process(events) { event in if event == 5 { throw BadEvent() } }
        }
    }
}
