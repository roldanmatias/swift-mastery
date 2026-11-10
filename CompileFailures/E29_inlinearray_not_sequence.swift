// expect: Iterable
func f() { let w: [3 of Int] = [1, 2, 3]; for x in w { _ = x } }
