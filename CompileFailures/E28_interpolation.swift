// expect: appendInterpolation
struct Token: ~Copyable { var a: Int }
func f(_ t: borrowing Token) -> String { "\(t)" }
