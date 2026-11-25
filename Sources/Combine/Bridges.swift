// Combine exercise — the bridges between Combine and Swift concurrency.
//
//   Combine ─▶ async   `publisher.values`, or `stream(of:)` below when you want the
//                      subscription to start now and to cancel when the loop ends
//   async ─▶ Combine   `taskPublisher`: run one async operation as a publisher
//                      that cancels the task when the subscriber cancels

import Combine

/// Wraps a publisher in an `AsyncStream`.
///
/// Unlike `publisher.values`, the subscription starts *when you call this*, not when
/// iteration begins, so nothing sent in between is lost. Ending the stream (cancelling the
/// consuming task, or releasing the last reference to the stream) cancels the Combine
/// subscription. Note that `break` alone does not end an `AsyncStream` that is still referenced.
///
/// `@MainActor` because Combine types aren't `Sendable`. The subscription lives in a
/// main-actor box (main-actor classes are `Sendable`), and `onTermination`, which can run
/// on any thread, hops to the main actor to cancel it. So cancellation is prompt, not instant.
@MainActor
package func stream<P: Publisher>(
    of publisher: P,
    bufferingPolicy: AsyncStream<P.Output>.Continuation.BufferingPolicy = .unbounded
) -> AsyncStream<P.Output> where P.Failure == Never, P.Output: Sendable {
    let (stream, continuation) = AsyncStream.makeStream(of: P.Output.self, bufferingPolicy: bufferingPolicy)
    let box = SubscriptionBox()
    box.subscription = publisher.sink(
        receiveCompletion: { _ in continuation.finish() },
        receiveValue: { continuation.yield($0) }
    )
    continuation.onTermination = { _ in
        Task { @MainActor in box.subscription?.cancel() }
    }
    return stream
}

@MainActor
private final class SubscriptionBox {
    var subscription: AnyCancellable?
}

/// Runs one async operation as a publisher: it emits the result once and completes.
/// Cancelling the subscription cancels the `Task`, which is what makes
/// `switchToLatest` stop the superseded work instead of merely ignoring it.
@MainActor
package func taskPublisher<Output: Sendable>(
    _ operation: @escaping @Sendable () async -> Output
) -> AnyPublisher<Output, Never> {
    let box = TaskBox()
    return Deferred {
        Future<Output, Never> { promise in
            // Runs on the main actor, so the non-Sendable `promise` never changes region.
            box.task = Task { promise(.success(await operation())) }
        }
    }
    .handleEvents(receiveCancel: { box.task?.cancel() })
    .eraseToAnyPublisher()
}

@MainActor
private final class TaskBox {
    var task: Task<Void, Never>?
}
