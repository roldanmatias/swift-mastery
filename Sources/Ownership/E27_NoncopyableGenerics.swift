// Ex 27 — Noncopyable generics (SE-0427).
//
// Every generic parameter, protocol and extension implicitly requires
// `Copyable`. `T: ~Copyable` *suppresses* that default: it means "T may or may
// not be Copyable", so the code must work for both.

enum E27 {
    struct Box<T: ~Copyable>: ~Copyable {
        var value: T

        init(_ value: consuming T) {
            self.value = value
        }
    }

    /// A slot holding an optional noncopyable value.
    struct LockSlot: ~Copyable {
        var lock: ReservationLock?

        init(_ lock: consuming ReservationLock?) {
            self.lock = lock
        }

        /// `Optional.take()` (SE-0437) moves the value out and leaves `nil`.
        mutating func takeLock() -> ReservationLock? {
            lock.take()
        }
    }
}

/// `Box<Int>` is Copyable; `Box<ReservationLock>` isn't.
extension E27.Box: Copyable where T: Copyable {}

extension E27.Box: Sendable where T: Sendable & ~Copyable {}

/// Members that must work for noncopyable `T` need `where T: ~Copyable`,
/// otherwise the extension silently adds `T: Copyable`.
extension E27.Box where T: ~Copyable {
    consuming func unwrap() -> T {
        value
    }

    borrowing func withValue<R>(_ body: (borrowing T) -> R) -> R {
        body(value)
    }

    consuming func map<U: ~Copyable>(_ transform: (consuming T) -> U) -> E27.Box<U> {
        E27.Box<U>(transform(value))
    }
}

/// Step 2 — the trap: no `where T: ~Copyable`, so this extension means
/// `where T: Copyable`. `Box<ReservationLock>().peek()` is rejected:
///   error: referencing instance method 'peek()' on 'E27.Box' requires that
///          'ReservationLock' conform to 'Copyable'
extension E27.Box {
    func peek() -> T { value }
}

// MARK: Step 3 — a protocol that noncopyable types can adopt

protocol Resource: ~Copyable {
    consuming func close() -> ReleaseReceipt
}

extension ReservationLock: Resource {
    consuming func close() -> ReleaseReceipt { release() }
}

enum ResourceOps {
    static func close<R: Resource & ~Copyable>(_ resource: consuming R) -> ReleaseReceipt {
        resource.close()
    }
}
