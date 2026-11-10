// expect: do not have matching underlying types
protocol P {}; struct A: P {}; struct B: P {}
func make(_ flag: Bool) -> some P { if flag { return A() } else { return B() } }
