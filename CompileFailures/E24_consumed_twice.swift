// expect: consumed more than once
struct Lock: ~Copyable { consuming func release() {} }
func f() { let lock = Lock(); lock.release(); lock.release() }
