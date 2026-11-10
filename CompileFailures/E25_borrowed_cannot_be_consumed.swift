// expect: is borrowed and cannot be consumed
struct Calendar { var days: [Int] = [] }
func duplicate(_ c: borrowing Calendar) -> Calendar { c }
