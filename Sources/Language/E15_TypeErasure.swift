// Ex 15 — Type erasure.

import Foundation

package enum E15 {
    enum BookingEvent: Hashable, Sendable {
        case held(String)
        case confirmed(String)
        case cancelled(String)
    }

    /// `send` is `mutating` so struct sinks can keep state. That makes the
    /// semantics of each erasure strategy observable (step 4).
    package protocol EventSink<Event> {
        associatedtype Event
        mutating func send(_ event: Event)
    }

    // MARK: Strategy 1 — closure-based eraser (+ Hashable identity)

    /// Hashable by *sink identity*, which is what `any EventSink<Event>` can't do:
    /// existentials don't conform to protocols, so `Set<any EventSink<E>>` is an error.
    package struct AnyEventSink<Event>: EventSink, Hashable {
        enum Identity: Hashable {
            case object(ObjectIdentifier)   // class sinks: real identity
            case token(UUID)                // value sinks: identity of this erasure
        }

        private let identity: Identity
        private let _send: (Event) -> Void

        /// Value sinks: the closure captures a `var` copy in a heap box, so
        /// all copies of this eraser SHARE that state (reference semantics!).
        package init<S: EventSink>(_ sink: S) where S.Event == Event {
            var sink = sink
            identity = .token(UUID())
            _send = { sink.send($0) }
        }

        /// Class sinks: more specific overload, picked for `AnyObject` sinks.
        /// Holding the object keeps it alive, so the `ObjectIdentifier` stays valid.
        package init<S: EventSink & AnyObject>(_ sink: S) where S.Event == Event {
            var sink = sink
            identity = .object(ObjectIdentifier(sink))
            _send = { sink.send($0) }
        }

        package func send(_ event: Event) { _send(event) }

        package static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }
        package func hash(into hasher: inout Hasher) { hasher.combine(identity) }
    }

    // MARK: Strategy 2 — class-box eraser with copy-on-write

    /// The box subclass hierarchy is the "manual witness table". Adding CoW on
    /// the box restores value semantics for stateful struct sinks.
    struct BoxedEventSink<Event>: EventSink {
        private class _Box {
            func send(_ event: Event) { fatalError("abstract") }
            func copy() -> _Box { fatalError("abstract") }
            func unwrap<S>(as type: S.Type) -> S? { fatalError("abstract") }
        }

        private final class _ConcreteBox<S: EventSink>: _Box where S.Event == Event {
            var sink: S
            init(_ sink: S) { self.sink = sink }
            override func send(_ event: Event) { sink.send(event) }
            override func copy() -> _Box { _ConcreteBox(sink) }
            override func unwrap<T>(as type: T.Type) -> T? { sink as? T }
        }

        private var box: _Box

        init<S: EventSink>(_ sink: S) where S.Event == Event {
            box = _ConcreteBox(sink)
        }

        mutating func send(_ event: Event) {
            if !isKnownUniquelyReferenced(&box) { box = box.copy() }
            box.send(event)
        }

        func unwrap<S>(as type: S.Type) -> S? { box.unwrap(as: type) }
    }

    // MARK: Sinks used by the tests

    /// Stateful value sink: reports how many events *this copy* has seen.
    struct CountingSink: EventSink {
        private(set) var count = 0
        private let report: (Int) -> Void
        init(report: @escaping (Int) -> Void = { _ in }) { self.report = report }
        mutating func send(_ event: BookingEvent) {
            count += 1
            report(count)
        }
    }

    final class RecordingSink: EventSink {
        private(set) var events: [BookingEvent] = []
        func send(_ event: BookingEvent) { events.append(event) }
    }

    /// The modern alternative: no wrapper type at all. Value semantics come for
    /// free (the existential box is copied with the value), but you can't make
    /// it Hashable or conform it to anything.
    static func fanOut(_ sinks: inout [any EventSink<BookingEvent>], _ event: BookingEvent) {
        for index in sinks.indices { sinks[index].send(event) }
    }
}
