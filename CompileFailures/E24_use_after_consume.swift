// expect: consumed more than once
struct Lock: ~Copyable { consuming func release() {} }
func f() { let lock = Lock(); let other = lock; lock.release(); _ = other }
