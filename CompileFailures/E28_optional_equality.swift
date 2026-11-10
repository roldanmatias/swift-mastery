// expect: requires that 'Token' conform to 'Copyable'
struct Token: ~Copyable, Hashable { var a: Int }
func f(_ a: borrowing Token?, _ b: borrowing Token?) -> Bool { a == b }
