// expect: does not conform to protocol 'Copyable'
struct Token: ~Copyable, Hashable { var a: Int }
let s: Set<Token> = []
