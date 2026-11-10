// expect: escaping closure
struct Lock: ~Copyable { consuming func release() {} }
func run(_ body: @escaping () -> Void) {}
func f() { let lock = Lock(); run { lock.release() } }
