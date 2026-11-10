// expect: conform to 'Copyable'
struct Box<T: ~Copyable>: ~Copyable { var value: T }
extension Box { func peek() -> T { value } }
struct Lock: ~Copyable {}
func f() { let b = Box(value: Lock()); _ = b.peek() }
