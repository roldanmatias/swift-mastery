// expect: inout arguments are not allowed to alias each other
func transfer(_ a: inout Int, _ b: inout Int) {}
func f() { var x = 10; transfer(&x, &x) }
